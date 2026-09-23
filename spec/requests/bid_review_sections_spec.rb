require "rails_helper"

RSpec.describe "投标专项清单与人工派办", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:analysis) { project.bid_analyses.create!(criteria: [ "服务计划" ], qualification_requirements: [ "原件第1章：登记证明" ], suggested_tasks: [ "核对登记证明原件" ]) }
  before { sign_in(admin) }

  it "编辑并显示四类清单，旧字段的局部请求不擦除新增人工内容" do
    patch bid_analysis_path(analysis), params: { bid_analysis: { qualification_requirements_text: "原件第1章：登记证明\n企业信息待核", disqualification_clauses_text: "原件第2章：超时提交无效", time_nodes_text: "原件第3章：截止2026-10-01 09:00，时区待核", suggested_tasks_text: "核对截止日期\n检查授权页" } }
    expect(analysis.reload.suggested_tasks).to eq([ "核对截止日期", "检查授权页" ])
    expect(analysis.criteria).to eq([ "服务计划" ])
    get bid_analysis_path(analysis)
    expect(response.body).to include("资格条件", "废标条款", "时间节点", "建议待办清单", "核对并创建任务")
    expect(AuditEvent.where(action: "bid_analysis.update")).to exist
    patch bid_analysis_path(analysis), params: { bid_analysis: { criteria_text: "人工新评分点" } }
    expect(analysis.reload.suggested_tasks).to eq([ "核对截止日期", "检查授权页" ])
    get edit_bid_analysis_path(analysis)
    expect(response.body).to include("bid_analysis_time_nodes_text", "检查授权页")
  end

  it "新建清单与审计同事务，审计失败不留下孤立分析" do
    allow(Audit::Recorder).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(analysis))
    expect do
      post project_bid_analyses_path(project), params: { bid_analysis: { criteria_text: "测试", suggested_tasks_text: "不能残留" } }
    end.not_to change(BidAnalysis, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "AI专项字段经过类型校验，错误字段整体拒绝，旧输出不擦除人工清单" do
    output = { criteria: [ "AI评分点" ], risks: [], outline: [], simulated_score: nil }
    run = AiRun.create!(record: analysis, project: project, requested_by: admin, task_type: "bid_analysis", status: "pending_review", output: output.merge(time_nodes: { bad: "日期" }).to_json)
    post approve_ai_run_path(run), params: { review_note: "核对" }
    expect(run.reload.status).to eq("pending_review")
    expect(analysis.reload.criteria).to eq([ "服务计划" ])
    run.update!(output: output.to_json)
    post approve_ai_run_path(run), params: { review_note: "旧输出兼容" }
    expect(run.reload.status).to eq("approved")
    expect(analysis.reload.suggested_tasks).to eq([ "核对登记证明原件" ])
    next_run = AiRun.create!(record: analysis, project: project, requested_by: admin, task_type: "bid_analysis", status: "pending_review", output: output.merge(qualification_requirements: [ "登记证明待核" ], disqualification_clauses: [], time_nodes: [], suggested_tasks: [ "核对供应商信息" ]).to_json)
    expect { post approve_ai_run_path(next_run), params: { review_note: "新清单核对" } }.not_to change(WorkflowTask, :count)
    expect(next_run.reload.status).to eq("approved")
    expect(analysis.reload.suggested_tasks).to eq([ "核对供应商信息" ])
    expect(Ai::PromptBuilder.for_bid_analysis(analysis).first).to include("qualification_requirements", "disqualification_clauses", "time_nodes", "suggested_tasks")
  end

  it "新增清单进入技术标依据，修改后旧文稿与旧AI建议失效" do
    draft = project.generated_documents.create!(created_by: admin, kind: "bid_technical", title: "合成技术标", content: "正文待核", bid_analysis: analysis, refresh_bid_basis: true)
    expect(draft.bid_basis_current?).to be(true)
    expect(draft.bid_basis_snapshot.dig("review_sections", "qualification_requirements")).to eq(analysis.qualification_requirements)
    get generated_document_path(draft)
    expect(response.body).to include("原件第1章：登记证明")
    run = AiRun.create!(record: analysis, project: project, requested_by: admin, task_type: "bid_analysis", status: "queued")
    analysis.update!(time_nodes: [ "新截止日期待核" ])
    expect(draft.bid_basis_current?).to be(false)
    expect(run.source_current?).to be(false)
  end

  it "建议入口仅预填不派发，确认后真实创建任务并通知办理人" do
    params = { record_ref: "BidAnalysis:#{analysis.public_id}", suggested_task_index: "0" }
    expect { get new_project_workflow_task_path(project), params: params }.not_to change(WorkflowTask, :count)
    expect(response.body).to include("核对登记证明原件")
    expect do
      post project_workflow_tasks_path(project), params: { workflow_task: { record_ref: params[:record_ref], stage: "人工确认：核对登记证明原件", assignee_id: admin.id, due_at: 1.day.from_now.iso8601 } }
    end.to change(WorkflowTask, :count).by(1)
    task = WorkflowTask.last
    expect(task.record).to eq(analysis)
    expect(task.stage).to include("人工确认")
    expect(Notification.where(user: admin, kind: "workflow.assigned")).to exist
    [ "-1", "abc", "9999" ].each do |index|
      get new_project_workflow_task_path(project), params: params.merge(suggested_task_index: index)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "只读成员不见AI和派办入口，跨项目建议与空复核请求安全拒绝" do
    post review_bid_analysis_path(analysis), params: {}
    expect(response).to redirect_to(analysis)
    expect(analysis.reload.status).not_to eq("reviewed")
    reader = create_user(email: "sections-reader@example.test")
    ProjectMembership.create!(project: project, user: reader, membership_role: "observer")
    other = create_project(owner: admin, code: "BID-SECTIONS-OTHER")
    foreign = other.bid_analyses.create!(suggested_tasks: [ "不可泄露" ])
    get new_project_workflow_task_path(project), params: { record_ref: "BidAnalysis:#{foreign.public_id}", suggested_task_index: "0" }
    expect(response).to have_http_status(:not_found)
    delete session_path
    sign_in(reader)
    get bid_analysis_path(analysis)
    expect(response.body).to include("原件第1章：登记证明")
    expect(response.body).not_to include("AI 辅助分析", "核对并创建任务")
    get new_project_workflow_task_path(project), params: { record_ref: "BidAnalysis:#{analysis.public_id}", suggested_task_index: "0" }
    expect(response).to redirect_to(root_path)
  end
end

require "rails_helper"

RSpec.describe "AI 版本与状态一致性", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:analysis) { project.bid_analyses.create!(status: "draft", criteria: [ "原评分点" ]) }
  let(:output) { { criteria: [ "AI 评分点" ], risks: [], outline: [], simulated_score: 80 }.to_json }
  let!(:run) { AiRun.create!(record: analysis, project: project, requested_by: admin, task_type: "bid_analysis", status: "pending_review", output: output) }
  before { sign_in(admin) }

  it "修改源数据后旧建议不覆盖，拒绝仍可保留审计结论" do
    analysis.update!(criteria: [ "人工新评分点" ])
    post approve_ai_run_path(run), params: { review_note: "尝试旧建议" }
    expect(response).to redirect_to(run)
    expect(run.reload.status).to eq("pending_review")
    expect(analysis.reload.criteria).to eq([ "人工新评分点" ])
    get ai_run_path(run)
    expect(response.body).to include("禁止应用此建议", "拒绝 AI 建议")
    expect(response.body).not_to include("人工批准并应用")
    post reject_ai_run_path(run), params: { review_note: "已过期，重新生成" }
    expect(run.reload.status).to eq("rejected")
  end

  it "项目资料新增或 OCR 内容改变使旧建议失效" do
    source = project.project_documents.create!(uploaded_by: admin, category: "tender", original_filename: "t.txt", content_type: "text/plain",
      file: { io: StringIO.new("new evidence"), filename: "t.txt", content_type: "text/plain" })
    expect(run.source_current?).to be(false)
    run.update!(source_fingerprint: Ai::SourceFingerprint.call(analysis))
    source.update!(ocr_text: "新的 OCR 内容")
    post approve_ai_run_path(run), params: { review_note: "基于旧 OCR" }
    expect(run.reload.status).to eq("pending_review")
    expect(analysis.reload.criteria).to eq([ "原评分点" ])
  end

  it "历史无指纹建议拒绝写回，不能自动当成当前版本" do
    run.update!(source_fingerprint: nil)
    post approve_ai_run_path(run), params: { review_note: "历史任务" }
    expect(run.reload.status).to eq("pending_review")
    expect(analysis.reload.criteria).to eq([ "原评分点" ])
  end

  it "批准重复提交和批准后拒绝均不再修改业务数据" do
    post approve_ai_run_path(run), params: { review_note: "已核对" }
    expect(run.reload.status).to eq("approved")
    count = AuditEvent.where(action: "bid_analysis.ai_apply").count
    post approve_ai_run_path(run), params: { review_note: "重复批准" }
    post reject_ai_run_path(run), params: { review_note: "迟到的拒绝" }
    expect(run.reload.status).to eq("approved")
    expect(AuditEvent.where(action: "bid_analysis.ai_apply").count).to eq(count)
  end

  it "AI 复核权限不隐含项目访问，成员撤权后不可批准" do
    reviewer = create_user(email: "ai-outsider@example.test", permissions: [ "ai.review" ])
    delete session_path
    sign_in(reviewer)
    post approve_ai_run_path(run), params: { review_note: "越界" }
    expect(run.reload.status).to eq("pending_review")
    membership = ProjectMembership.create!(project: project, user: reviewer, membership_role: "member")
    membership.destroy!
    post reject_ai_run_path(run), params: { review_note: "撤权后拒绝" }
    expect(run.reload.status).to eq("pending_review")
  end

  it "已定稿文稿不因 AI 建议重新变为草稿" do
    doc = project.generated_documents.create!(created_by: admin, kind: "general", title: "原题", content: "原文", status: "draft")
    draft_run = AiRun.create!(project: project, record: doc, requested_by: admin, task_type: "draft_document", status: "pending_review", output: { title: "新题", content: "新文", warnings: [] }.to_json)
    doc.update!(status: "approved", approved_by: admin, approved_at: Time.current, review_note: "已定稿")
    post approve_ai_run_path(draft_run), params: { review_note: "覆盖定稿" }
    expect(doc.reload.status).to eq("approved")
    expect(doc.content).to eq("原文")
    expect(draft_run.reload.status).to eq("pending_review")
    allow(Ai::OpenaiCompatibleClient).to receive(:configured?).and_return(true)
    expect { post ai_suggest_generated_document_path(doc) }.not_to change(AiRun, :count)
  end

  it "无效分数及空复核说明事务回滚，不留下部分写回" do
    run.update!(output: { criteria: [ "污染" ], risks: [], outline: [], simulated_score: "not a number" }.to_json)
    post approve_ai_run_path(run), params: { review_note: "无效分数" }
    expect(run.reload.status).to eq("pending_review")
    expect(analysis.reload.criteria).to eq([ "原评分点" ])
    run.update!(output: output)
    post approve_ai_run_path(run), params: { review_note: "   " }
    expect(run.reload.status).to eq("pending_review")
    expect(analysis.reload.criteria).to eq([ "原评分点" ])
    expect(AuditEvent.where(action: "bid_analysis.ai_apply")).not_to exist
  end

  it "重复投递同一个后台任务只调用供应商一次，源过期任务不调用" do
    run.update!(status: "queued")
    client = instance_double(Ai::OpenaiCompatibleClient, provider: "test", model: "test")
    allow(Ai::OpenaiCompatibleClient).to receive(:new).and_return(client)
    expect(client).to receive(:chat).once.and_return(content: output)
    Ai::RunJob.perform_now(run.id)
    Ai::RunJob.perform_now(run.id)
    expect(run.reload.status).to eq("pending_review")
    run.update!(status: "queued")
    analysis.update!(risks: [ "新风险" ])
    Ai::RunJob.perform_now(run.id)
    expect(run.reload.status).to eq("failed")
  end

  it "JSON 非对象和错误字段类型安全拒绝，不产生 500 或业务写入" do
    [ "null", "[]", '"text"', '{"criteria":123,"risks":[],"outline":[]}' ].each do |invalid|
      run.update!(output: invalid)
      post approve_ai_run_path(run), params: { review_note: "核验" }
      expect(response).to redirect_to(run)
      expect(run.reload.status).to eq("pending_review")
      expect(analysis.reload.criteria).to eq([ "原评分点" ])
    end
    post reject_ai_run_path(run), params: { review_note: "  " }
    expect(response).to redirect_to(run)
    expect(run.reload.status).to eq("pending_review")
  end

  it "排队与待复核期间重复创建不新增任务，终态后可重新发起" do
    allow(Ai::OpenaiCompatibleClient).to receive(:configured?).and_return(true)
    expect { post ai_suggest_bid_analysis_path(analysis) }.not_to change(AiRun, :count)
    run.update!(status: "failed")
    expect { post ai_suggest_bid_analysis_path(analysis) }.to change(AiRun, :count).by(1)
    expect { post ai_suggest_bid_analysis_path(analysis) }.not_to change(AiRun, :count)
    expect(AiRun.last.source_fingerprint).to match(/\A[0-9a-f]{64}\z/)
  end
end

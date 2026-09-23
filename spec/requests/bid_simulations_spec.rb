require "rails_helper"

RSpec.describe "完整投标文件 AI 模拟审核", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:analysis) { project.bid_analyses.create!(status: "draft", criteria: [ "服务方案" ]) }
  let!(:score) { analysis.bid_scores.create!(updated_by: admin, criterion: "服务方案", maximum: 100, awarded: 12.34, rationale: "人工自评不得进入AI标准", scoring_rule: "方案包含完整服务计划可得100分，否则按缺失程度扣分", requires_evidence: false, evidence_exception: "依据方案文本") }
  let!(:document) { project.generated_documents.create!(created_by: admin, kind: "bid_technical", title: "合成完整技术标", content: "第一章\n我们提供完整服务计划及人员安排。\n结束标记", status: "draft") }
  before { sign_in(admin) }

  def create_simulation(**values)
    post bid_analysis_bid_simulations_path(analysis), params: { source_ref: "generated:#{document.public_id}", bid_simulation: { title: "全文验收", confirmed_complete: true }.merge(values) }
    analysis.bid_simulations.last
  end

  def output(awarded: 80, excerpt: "我们提供完整服务计划及人员安排。")
    { scores: [ { criterion_id: score.public_id, awarded: awarded, reason: "方案存在，但质量保障仍需核对", location: "第一章", excerpt: excerpt, missing_evidence: [ "质量保障附件待核" ] } ], warnings: [ "合成测试，不作为实际评标意见" ] }
  end

  def pending(simulation, result = output)
    AiRun.create!(record: simulation, project: project, requested_by: admin, task_type: "bid_simulation", status: "pending_review", output: result.to_json)
  end

  it "完整文本快照与独立评分原文进入提示词，不混入人工自评分" do
    document.update!(content: "前言" + "完整正文。" * 5000 + "全文尾部标记")
    simulation = create_simulation
    expect(response).to redirect_to(simulation)
    _system, prompt = Ai::PromptBuilder.for_bid_simulation(simulation)
    expect(prompt).to include("全文尾部标记", score.scoring_rule)
    expect(simulation.source_text).to eq(document.content)
    expect(prompt).not_to include("12.34", "人工自评不得进入AI标准")
    get bid_simulation_path(simulation)
    expect(response.body).to include("本次全文与量表快照", "发起 AI 模拟审核")
  end

  it "真实任务路径生成并人工批准独立结果，不覆盖手工评分和投标文稿" do
    simulation = create_simulation
    allow(Ai::OpenaiCompatibleClient).to receive(:configured?).and_return(true)
    client = instance_double(Ai::OpenaiCompatibleClient, provider: "test", model: "test")
    allow(Ai::OpenaiCompatibleClient).to receive(:new).and_return(client)
    expect(client).to receive(:chat).with(system: include("逐项评分"), user: include("结束标记")).and_return(content: output.to_json)
    post ai_suggest_bid_simulation_path(simulation)
    run = simulation.ai_runs.last!
    Ai::RunJob.perform_now(run.id)
    expect(run.reload.status).to eq("pending_review")
    expect(run.input_scope).to include("mode" => "full_submission", "included_characters" => document.content.length)
    expect(run.input_scope["documents"].first).to include("truncated" => false, "excerpt_sha256" => Digest::SHA256.hexdigest(document.content))
    expect(run.evidence_refs).to eq([ document.public_id ])
    post approve_ai_run_path(run), params: { review_note: "核对原文，仅保留模拟建议" }
    expect(simulation.reload.status).to eq("reviewed")
    expect(simulation.total_score).to eq(80)
    expect(simulation.results.first["criterion"]).to eq("服务方案")
    expect(score.reload.awarded).to eq(BigDecimal("12.34"))
    expect(document.reload.content).to include("结束标记")
    expect(analysis.reload.simulated_score).to be_nil
    expect(AuditEvent.where(action: "bid_simulation.ai_apply")).to exist
  end

  it "缺确认、缺规则、非完整量表和超长全文拒绝保存，不静默截断" do
    expect { create_simulation(confirmed_complete: false) }.not_to change(BidSimulation, :count)
    score.update!(scoring_rule: nil)
    expect { create_simulation }.not_to change(BidSimulation, :count)
    score.update!(scoring_rule: "规则", maximum: 90)
    expect { create_simulation }.not_to change(BidSimulation, :count)
    score.update!(maximum: 100)
    document.update!(content: "长" * 100_001)
    expect { create_simulation }.not_to change(BidSimulation, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("未截断或提交")
  end

  it "项目文件需解析完成，且不能引用其他项目的文稿" do
    file = project.project_documents.create!(uploaded_by: admin, category: "bid", original_filename: "full.txt", ocr_text: "提取文字",
      file: { io: StringIO.new("source"), filename: "full.txt", content_type: "text/plain" })
    params = { source_ref: "file:#{file.public_id}", bid_simulation: { title: "文件审核", confirmed_complete: true } }
    expect { post bid_analysis_bid_simulations_path(analysis), params: params }.not_to change(BidSimulation, :count)
    file.update!(ocr_status: "completed")
    expect { post bid_analysis_bid_simulations_path(analysis), params: params }.to change(BidSimulation, :count).by(1)
    other = create_project(owner: admin, code: "SIM-OTHER")
    foreign = other.generated_documents.create!(created_by: admin, kind: "bid_technical", title: "其他文稿", content: "不能越界", status: "draft")
    post bid_analysis_bid_simulations_path(analysis), params: params.merge(source_ref: "generated:#{foreign.public_id}")
    expect(response).to have_http_status(:not_found)
  end

  it "伪造引用、超分、重复或遗漏评分点均不能被人工批准写入" do
    simulation = create_simulation
    invalids = [
      output(excerpt: "虚构的不存在片段"), output(awarded: 101), output(excerpt: ""),
      { scores: [], warnings: [] }, { scores: output[:scores] * 2, warnings: [] },
      output(awarded: "80")
    ]
    invalids.each do |data|
      run = pending(simulation, data)
      post approve_ai_run_path(run), params: { review_note: "错误输出不能通过" }
      expect(response).to redirect_to(run)
      expect(run.reload.status).to eq("pending_review")
      expect(simulation.reload.results).to be_empty
    end
  end

  it "无法判断的条目保留空分值，不伪造总分" do
    simulation = create_simulation
    run = pending(simulation, output(awarded: nil, excerpt: ""))
    post approve_ai_run_path(run), params: { review_note: "资料不足，只保留待核事项" }
    expect(simulation.reload.status).to eq("reviewed")
    expect(simulation.total_score).to be_nil
    expect(simulation.results.first["awarded"]).to be_nil
  end

  it "审批页面先展示可读逐项预览，GET不写回，非法输出无批准入口" do
    simulation = create_simulation
    run = pending(simulation)
    get ai_run_path(run)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("逐项模拟建议预览", "80.00", "不修改人工自评分和文稿正文")
    expect(simulation.reload.results).to be_empty
    expect(run.reload.status).to eq("pending_review")
    run.update!(output: output(excerpt: "不存在的引用").to_json)
    get ai_run_path(run)
    expect(response.body).to include("无法形成安全评分预览", "拒绝 AI 建议")
    expect(response.body).not_to include("人工批准并应用")
  end

  it "非法量表结构按验证错误拒绝而不是崩溃" do
    simulation = create_simulation
    [ nil, {}, [ nil ], [ {} ], [ simulation.rubric.first.merge("maximum" => "NaN") ],
      [ simulation.rubric.first.merge("maximum" => "Infinity") ], [ simulation.rubric.first.merge("maximum" => "错误") ] ].each do |rubric|
      simulation.rubric = rubric
      expect(simulation).not_to be_valid
      expect(simulation.errors[:rubric]).to be_present
    end
  end

  it "评分维护请求持久化独立标准，新批次使用保存后的规则" do
    patch bid_analysis_bid_score_path(analysis, score), params: { bid_score: { scoring_rule: "新合成标准：三步计划完整得100分" } }
    expect(response).to redirect_to(analysis)
    expect(score.reload.scoring_rule).to eq("新合成标准：三步计划完整得100分")
    simulation = create_simulation
    expect(simulation.rubric.first["rule"]).to eq(score.scoring_rule)
  end

  it "文稿或评分标准修改后旧快照失效，历史内容仍保留" do
    simulation = create_simulation
    run = pending(simulation)
    document.update!(content: "新版本全文")
    post approve_ai_run_path(run), params: { review_note: "旧版" }
    expect(run.reload.status).to eq("pending_review")
    expect(simulation.reload.source_text).to include("结束标记")
    get bid_simulation_path(simulation)
    expect(response.body).to include("当前文档或评分标准已变化")
    another = create_simulation
    score.update!(scoring_rule: "新的扣分标准")
    expect(another.current_basis?).to be(false)
  end

  it "观察者不能创建或执行模拟，跨项目AI复核权限不可越界" do
    simulation = create_simulation
    run = pending(simulation)
    reviewer = create_user(email: "sim-reviewer@example.test", permissions: [ "ai.review" ])
    delete session_path
    sign_in(reviewer)
    get bid_simulation_path(simulation)
    expect(response).to have_http_status(:redirect)
    post approve_ai_run_path(run), params: { review_note: "越权" }
    expect(run.reload.status).to eq("pending_review")
    ProjectMembership.create!(project: project, user: reviewer, membership_role: "observer")
    get bid_simulation_path(simulation)
    expect(response).to have_http_status(:ok)
    expect { create_simulation }.not_to change(BidSimulation, :count)
    expect { post ai_suggest_bid_simulation_path(simulation) }.not_to change(AiRun, :count)
  end
end

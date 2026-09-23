require "rails_helper"

RSpec.describe "AI 人工复核", type: :request do
  let!(:admin) { create_user(admin: true, email: "ai-review@example.com") }
  let!(:project) { create_project(owner: admin, code: "AI-RVW-001", name: "AI 复核项目") }
  let!(:analysis) { BidAnalysis.create!(project: project, status: "draft", criteria: [ "旧评分点" ], risks: [], outline: [], simulated_score: 60) }

  before { sign_in(admin) }

  it "在配置缺失时不创建任务且不调用供应商" do
    allow(Ai::OpenaiCompatibleClient).to receive(:configured?).and_return(false)

    expect do
      post ai_suggest_bid_analysis_path(analysis)
    end.not_to change(AiRun, :count)
    expect(response).to redirect_to(bid_analysis_path(analysis))
  end

  it "人工批准合法 JSON 后写回草稿并保留复核证据" do
    run = AiRun.create!(
      project: project,
      record: analysis,
      requested_by: admin,
      task_type: "bid_analysis",
      status: "pending_review",
      output: '{"criteria":["评分点A","评分点B"],"risks":["核验证书"],"outline":["项目理解"],"simulated_score":88}'
    )

    post approve_ai_run_path(run), params: { review_note: "已核对原始招标文件，批准写回草稿。" }

    expect(response).to redirect_to(bid_analysis_path(analysis))
    expect(run.reload.status).to eq("approved")
    expect(run.reviewed_by).to eq(admin)
    expect(analysis.reload.criteria).to eq([ "评分点A", "评分点B" ])
    expect(analysis.simulated_score).to eq(88)
    expect(AuditEvent.where(action: "bid_analysis.ai_apply", record_id: analysis.id)).to exist
  end

  it "拒绝建议时不修改业务分析" do
    run = AiRun.create!(project: project, record: analysis, requested_by: admin, task_type: "bid_analysis", status: "pending_review", output: "{}")

    post reject_ai_run_path(run), params: { review_note: "输出缺少原文依据。" }

    expect(run.reload.status).to eq("rejected")
    expect(analysis.reload.criteria).to eq([ "旧评分点" ])
  end

  it "人工批准债权分析后仅写入候选分类和风险证据" do
    claim = Claim.create!(project: project, created_by: admin, creditor_name: "示例债权人", claim_amount: 100_000, currency: "CNY", claimed_type: "unknown", status: "received")
    run = AiRun.create!(
      project: project,
      record: claim,
      requested_by: admin,
      task_type: "claim_analysis",
      status: "pending_review",
      output: { recommended_type: "ordinary", risk_level: "medium", analysis_summary: "合同与付款金额需进一步核对。", conflicts: [ "发票金额不一致" ], legal_basis: [ "相关条文需核对现行有效性" ], missing_evidence: [ "付款流水" ] }.to_json
    )

    post approve_ai_run_path(run), params: { review_note: "已核对来源文件，同意作为候选意见。" }

    expect(response).to redirect_to(claim_path(claim))
    expect(claim.reload.recommended_type).to eq("ordinary")
    expect(claim.risk_level).to eq("medium")
    expect(claim.analysis_data["conflicts"]).to eq([ "发票金额不一致" ])
    expect(claim.status).to eq("received")
    expect(AuditEvent.where(action: "claim.ai_apply", record_id: claim.id)).to exist
  end

  it "AI 文稿经建议批准后仍保持草稿状态等待业务审批" do
    document = GeneratedDocument.create!(project: project, created_by: admin, kind: "bid_technical", title: "旧标题", content: "旧草稿", status: "draft")
    run = AiRun.create!(project: project, record: document, requested_by: admin, task_type: "draft_document", status: "pending_review", output: { title: "技术标初稿", content: "基于已提供资料形成的正文", warnings: [ "人员证书待核验" ] }.to_json)

    post approve_ai_run_path(run), params: { review_note: "仅批准写回草稿，尚未业务定稿。" }

    expect(response).to redirect_to(generated_document_path(document))
    expect(document.reload.content).to eq("基于已提供资料形成的正文")
    expect(document.ai_warnings).to eq([ "人员证书待核验" ])
    expect(document.status).to eq("draft")
    expect(document.approved_by).to be_nil
    expect(AuditEvent.where(action: "generated_document.ai_apply", record_id: document.id)).to exist
  end
end

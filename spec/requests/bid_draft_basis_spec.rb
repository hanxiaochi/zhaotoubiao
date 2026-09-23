require "rails_helper"

RSpec.describe "技术标起草依据与资质联动", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:analysis) { project.bid_analyses.create!(status: "draft", criteria: [ "团队资质" ], outline: [ "项目理解", "人员方案" ]) }
  let!(:entry) do
    LibraryEntry.create!(created_by: admin, kind: "qualification", title: "合成资质证书", organization: "合成企业", description: "仅合成资质事实", expires_on: Date.current + 30,
      documents: [ { io: StringIO.new("synthetic proof"), filename: "proof.txt", content_type: "text/plain" } ])
  end
  let!(:evidence) { analysis.bid_evidences.create!(created_by: admin, library_entry: entry, criterion: "团队资质", note: "仅用于合成测试", page_reference: "附件一", source_snapshot: entry.evidence_snapshot) }
  before { sign_in(admin) }

  def create_draft
    post project_generated_documents_path(project), params: { generated_document: { kind: "bid_technical", title: "合成技术标", content: "待核对的正文", bid_analysis_public_id: analysis.public_id } }
    expect(response).to have_http_status(:redirect)
    project.generated_documents.last!
  end

  it "从分析进入草稿，持久保存所选评分点与证明快照并传入 AI 提示词" do
    get new_project_generated_document_path(project, kind: "bid_technical", bid_analysis_id: analysis.public_id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("项目理解", "人员方案", "关联投标分析")
    draft = create_draft
    expect(draft.bid_basis_snapshot.fetch("criteria")).to eq([ "团队资质" ])
    expect(draft.bid_basis_snapshot.fetch("evidence").first.fetch("source").fetch("title")).to eq("合成资质证书")
    expect(Ai::PromptBuilder.for_draft_document(draft).last).to include("团队资质", "合成资质证书", "附件一")
    get generated_document_path(draft)
    expect(response.body).to include("投标起草依据", "依据与当前版本一致")
    expect(AuditEvent.where(action: "generated_document.create", record_type: "GeneratedDocument", record_id: draft.id)).to exist
  end

  it "跨项目和伪造快照参数不能关联或注入他项目资料" do
    other = create_project(owner: create_user(email: "other-draft@example.test"), code: "OTHER-DRAFT")
    foreign = other.bid_analyses.create!(criteria: [ "不得泄露" ])
    expect do
      post project_generated_documents_path(project), params: { generated_document: { kind: "bid_technical", title: "越界", content: "x", bid_analysis_public_id: foreign.public_id, bid_basis_snapshot: { criteria: [ "注入" ] } } }
    end.not_to change(GeneratedDocument, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "过期归档证明不把原资质内容提供给 AI，仅列不可用警告" do
    entry.update!(status: "archived")
    draft = create_draft
    prompt = Ai::PromptBuilder.for_draft_document(draft).last
    expect(prompt).to include("不得用于声明资质与业绩")
    expect(prompt).not_to include("仅合成资质事实", "合成资质证书")
    expect(draft.bid_basis_snapshot.fetch("evidence").first.fetch("usable")).to be(false)
  end

  it "依据变化阻断旧文稿提交及旧 AI 应用，明确刷新后才能重新提交" do
    draft = create_draft
    run = AiRun.create!(project: project, record: draft, requested_by: admin, task_type: "draft_document", status: "pending_review", output: { title: "旧建议", content: "旧建议正文", warnings: [] }.to_json)
    analysis.update!(outline: [ "新人员方案" ])
    post submit_generated_document_path(draft)
    expect(response).to redirect_to(draft)
    expect(draft.reload.status).to eq("draft")
    expect(run.source_current?).to be(false)
    post approve_ai_run_path(run), params: { review_note: "尝试旧依据" }
    expect(draft.reload.content).to eq("待核对的正文")
    expect(run.reload.status).to eq("pending_review")
    patch generated_document_path(draft), params: { generated_document: { content: "已核对新的人员方案", refresh_bid_basis: "1" } }
    expect(draft.reload.bid_basis_snapshot.fetch("outline")).to eq([ "新人员方案" ])
    post submit_generated_document_path(draft)
    expect(draft.reload.status).to eq("pending_review")
  end

  it "提交后资质过期不能通过审批，退回保留旧快照和审批意见" do
    draft = create_draft
    post submit_generated_document_path(draft)
    entry.update!(expires_on: Date.yesterday)
    post approve_generated_document_path(draft), params: { review_note: "尝试过期依据" }
    expect(response).to redirect_to(draft)
    expect(draft.reload.status).to eq("pending_review")
    post reject_generated_document_path(draft), params: { review_note: "资质已过期，请补充" }
    expect(draft.reload.status).to eq("rejected")
    expect(draft.bid_basis_snapshot.fetch("evidence").first.fetch("usable")).to be(true)
    expect(draft.review_note).to include("资质已过期")
  end

  it "未关联的普通文稿保持原工作流，空审批意见友好拒绝" do
    draft = project.generated_documents.create!(created_by: admin, kind: "general", title: "普通文稿", content: "正文")
    post submit_generated_document_path(draft)
    post approve_generated_document_path(draft), params: { review_note: " " }
    expect(response).to redirect_to(draft)
    expect(draft.reload.status).to eq("pending_review")
    post approve_generated_document_path(draft), params: { review_note: "核对通过" }
    expect(draft.reload.status).to eq("approved")
  end
end

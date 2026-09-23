require "rails_helper"

RSpec.describe "AI 实际输入范围", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:analysis) { project.bid_analyses.create!(status: "draft", criteria: []) }

  def document(text:, status: "uploaded", project: self.project)
    project.project_documents.create!(uploaded_by: admin, category: "tender", status: status,
      original_filename: "source.txt", ocr_text: text,
      file: { io: StringIO.new("fixture"), filename: "source.txt", content_type: "text/plain" })
  end

  it "稳定取前六份，排除归档与空白文本并明确字符截断" do
    first = document(text: "甲" * 20_000 + "不得发送的尾部")
    6.times { |i| document(text: "资料#{i}") }
    archived = document(text: "归档秘密", status: "archived")
    document(text: "  ")
    context = Ai::DocumentContext.new(analysis, "bid_analysis")
    expect(context.evidence_refs).to eq(project.project_documents.order(:id).first(6).map(&:public_id))
    expect(context.evidence_refs).not_to include(archived.public_id)
    expect(context.snapshot).to include("omitted_documents" => 1, "archived_documents" => 1, "without_text_documents" => 1)
    expect(context.snapshot["documents"].first).to include("public_id" => first.public_id, "included_characters" => 20_000, "truncated" => true)
    expect(context.prompt).to include("不是完整案卷", "超限未纳入1份", "归档1份")
    expect(context.prompt).not_to include("不得发送的尾部", "归档秘密", "资料5")
    expect(Ai::PromptBuilder.for_bid_analysis(analysis, context: context).last).to include(context.prompt)
  end

  it "债权只包含本项目关联文件并去重，拒绝跨项目错误关联" do
    claim = project.claims.create!(created_by: admin, creditor_name: "合成债权人", claim_amount: 10, currency: "CNY", claimed_type: "ordinary")
    linked = document(text: "关联内容")
    other = document(text: "跨项目内容", project: create_project(owner: admin, code: "AI-OTHER"))
    2.times { |i| claim.claim_materials.create!(material_type: "contract#{i}", project_document: linked) }
    # Simulate a legacy invalid row; ordinary model writes already reject this association.
    claim.claim_materials.create!(material_type: "legacy").update_column(:project_document_id, other.id)
    document(text: "未关联内容")
    context = Ai::DocumentContext.new(claim, "claim_analysis")
    expect(context.evidence_refs).to eq([ linked.public_id ])
    expect(context.prompt).not_to include("跨项目内容", "未关联内容")
    expect(Ai::PromptBuilder.for_claim_analysis(claim, context: context).last).to include(context.prompt)
  end

  it "文稿最多八份，债权最多十二份并公开遗漏数" do
    claim = project.claims.create!(created_by: admin, creditor_name: "合成债权人", claim_amount: 10, currency: "CNY", claimed_type: "ordinary")
    13.times do |i|
      source = document(text: "资料#{i}")
      claim.claim_materials.create!(material_type: "contract#{i}", project_document: source)
    end
    draft = project.generated_documents.create!(created_by: admin, kind: "general", title: "草稿", content: "人工输入", status: "draft")
    context = Ai::DocumentContext.new(draft, "draft_document")
    expect(context.evidence_refs.length).to eq(8)
    expect(context.snapshot["omitted_documents"]).to eq(5)
    expect(Ai::PromptBuilder.for_draft_document(draft, context: context).last).to include(context.prompt)
    expect(Ai::DocumentContext.new(claim, "claim_analysis").snapshot).to include("omitted_documents" => 1, "document_limit" => 12)
  end

  it "后台实际发送与持久化范围完全一致，页面公开范围且旧任务不虚构范围" do
    source = document(text: "合成可发送内容")
    document(text: "不可发送归档", status: "archived")
    run = AiRun.create!(record: analysis, project: project, requested_by: admin, task_type: "bid_analysis", status: "queued")
    client = instance_double(Ai::OpenaiCompatibleClient, provider: "test", model: "test")
    allow(Ai::OpenaiCompatibleClient).to receive(:new).and_return(client)
    expect(client).to receive(:chat) do |system:, user:|
      expect(system).to be_present
      expect(user).to include(source.public_id, "合成可发送内容")
      expect(user).not_to include("不可发送归档")
      { content: { criteria: [], risks: [], outline: [], simulated_score: nil }.to_json }
    end
    Ai::RunJob.perform_now(run.id)
    expect(run.reload.status).to eq("pending_review")
    expect(run.evidence_refs).to eq([ source.public_id ])
    expect(run.input_scope["documents"].first["excerpt_sha256"]).to eq(Digest::SHA256.hexdigest(source.ocr_text))
    sign_in(admin)
    get ai_run_path(run)
    expect(response.body).to include("实际 AI 输入范围", "仅摘录分析", "已归档排除 1 份")
    run.update!(input_scope: {})
    get ai_run_path(run)
    expect(response.body).to include("历史任务未记录输入范围")
    source.update!(ocr_text: "已变更")
    expect(run.source_current?).to be(false)
  end
end

require "rails_helper"

RSpec.describe "核心业务闭环", type: :request do
  let!(:admin) { create_user(admin: true, email: "admin@example.com") }

  before { sign_in(admin) }

  it "创建、查看并更新项目，同时写入审计轨迹" do
    expect do
      post projects_path, params: { project: { code: "PH-2026-001", name: "东华破产项目", project_type: "bankruptcy", status: "active", start_date: Date.current, due_date: 30.days.from_now.to_date, description: "测试项目" } }
    end.to change(Project, :count).by(1).and change(AuditEvent, :count).by(1)

    project = Project.find_by!(code: "PH-2026-001")
    expect(project.owner).to eq(admin)
    expect(project.members).to include(admin)
    expect(response).to redirect_to(project_path(project))

    get project_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("东华破产项目")

    patch project_path(project), params: { project: { code: project.code, name: "更新后的项目", project_type: project.project_type, status: "reviewing", start_date: project.start_date } }
    expect(project.reload.name).to eq("更新后的项目")
    expect(project.status).to eq("reviewing")
    expect(AuditEvent.where(action: "project.update", record_id: project.id)).to exist
  end

  it "为资产保留每次价值变化的业务版本和修改原因" do
    project = create_project(owner: admin)

    expect do
      post project_assets_path(project), params: { asset: { asset_code: "AS-001", name: "办公楼", category: "房产", appraisal_value: 10_000_000, disposal_status: "pending", change_reason: "接管清册首次登记" } }
    end.to change(Asset, :count).by(1).and change(AssetVersion, :count).by(1)

    asset = Asset.find_by!(asset_code: "AS-001")
    expect(asset.asset_versions.first.change_reason).to eq("接管清册首次登记")

    patch project_asset_path(project, asset), params: { asset: { asset_code: asset.asset_code, name: asset.name, category: asset.category, appraisal_value: 9_500_000, disposal_status: "verified", change_reason: "依据正式评估报告调整" } }
    expect(response).to redirect_to(project_path(project))
    expect(asset.reload.appraisal_value).to eq(9_500_000)
    expect(asset.asset_versions.order(:created_at).pluck(:change_reason)).to eq([ "接管清册首次登记", "依据正式评估报告调整" ])
  end

  it "生成债权材料清单、计算完整度并记录多级审核" do
    project = create_project(owner: admin)

    expect do
      post project_claims_path(project), params: { claim: { creditor_name: "示例债权人", claim_amount: 500_000, currency: "CNY", claimed_type: "ordinary", summary: "合同款项" } }
    end.to change(Claim, :count).by(1).and change(ClaimMaterial, :count).by(7)

    claim = Claim.find_by!(creditor_name: "示例债权人")
    expect(claim.reload.completeness_score).to eq(0)
    material = claim.claim_materials.first

    patch claim_claim_material_path(claim, material), params: { claim_material: { present: true, signature_detected: true, seal_detected: true, page_reference: "第1-3页" } }
    expect(material.reload.checked_by).to eq(admin)
    expect(claim.reload.completeness_score).to eq(14.29)

    expect do
      post review_claim_path(claim), params: { stage: "initial", decision: "request_supplement", comment: "请补充付款凭证原件。" }
    end.to change(ClaimReview, :count).by(1)
    expect(claim.reload.status).to eq("supplement_required")
    expect(AuditEvent.where(action: "claim.review", record_id: claim.id)).to exist
  end

  it "维护接管资料清单和收费台账" do
    project = create_project(owner: admin)
    attachment = fixture_file_upload(Rails.root.join("spec/fixtures/files/evidence.txt"), "text/plain")

    expect do
      post project_intake_items_path(project), params: { intake_item: { category: "证照", name: "营业执照原件", status: "received", custodian: "项目组", received_at: Time.current, note: "现场交接", attachments: [ attachment ] } }
    end.to change(IntakeItem, :count).by(1)
    item = IntakeItem.find_by!(name: "营业执照原件")
    expect(item.created_by).to eq(admin)
    expect(item.attachments).to be_attached

    patch project_intake_item_path(project, item), params: { intake_item: { category: item.category, name: item.name, status: "archived", custodian: item.custodian } }
    expect(item.reload.status).to eq("archived")

    expect do
      post project_fees_path(project), params: { fee: { fee_type: "agency", receivable: 100_000, received: 40_000, received_on: Date.current, invoice_status: "issued", note: "首期款" } }
    end.to change(Fee, :count).by(1)
    fee = Fee.last
    expect(fee.outstanding).to eq(60_000)
    expect(AuditEvent.where(action: %w[intake.create intake.update fee.create]).count).to eq(3)
  end

  it "上传项目文件、保存摘要、阻止同项目重复文件并支持归档" do
    project = create_project(owner: admin)
    upload = fixture_file_upload(Rails.root.join("spec/fixtures/files/evidence.txt"), "text/plain")

    expect do
      post project_project_documents_path(project), params: { project_document: { category: "claim", file: upload } }
    end.to change(ProjectDocument, :count).by(1)
    document = ProjectDocument.last
    expect(document.file).to be_attached
    expect(document.sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(document.ocr_status).to eq("not_required")

    duplicate = fixture_file_upload(Rails.root.join("spec/fixtures/files/evidence.txt"), "text/plain")
    post project_project_documents_path(project), params: { project_document: { category: "other", file: duplicate } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(ProjectDocument.count).to eq(1)

    patch archive_project_project_document_path(project, document)
    expect(document.reload.status).to eq("archived")
    expect(AuditEvent.where(action: "document.archive", record_id: document.id)).to exist
  end

  it "从 OCR 字段预填债权并关联材料来源与置信度" do
    project = create_project(owner: admin, code: "OCR-CLAIM")
    path = Rails.root.join("spec/fixtures/files/evidence.txt")
    document = ProjectDocument.new(
      project: project,
      uploaded_by: admin,
      category: "claim",
      status: "uploaded",
      original_filename: "claim.txt",
      content_type: "text/plain",
      byte_size: File.size(path),
      sha256: Digest::SHA256.file(path).hexdigest,
      ocr_status: "completed",
      analysis_status: "pending",
      ocr_text: "债权申报书",
      metadata: { "classification" => "债权申报书", "classification_confidence" => 85, "extracted_fields" => { "creditor_name" => "OCR 债权人", "claim_amount" => "12345.67" }, "field_sources" => { "creditor_name" => { "page" => 1 } } }
    )
    document.file.attach(io: File.open(path, "rb"), filename: "claim.txt", content_type: "text/plain")
    document.save!

    get new_project_claim_path(project, source_document_id: document.public_id)
    expect(response.body).to include("OCR 债权人", "12345.67")

    post project_claims_path(project), params: { source_document_id: document.public_id, claim: { creditor_name: "OCR 债权人", claim_amount: 12_345.67, currency: "CNY", claimed_type: "unknown" } }
    claim = Claim.find_by!(creditor_name: "OCR 债权人")
    material = claim.claim_materials.find_by!(material_type: "债权申报书")
    expect(material.project_document).to eq(document)
    expect(material.extraction_confidence).to eq(85)
    expect(material.present).to be(true)
  end

  it "按四级顺序流转债权审核并阻止跳级" do
    project = create_project(owner: admin, code: "CLAIM-FLOW")
    claim = Claim.create!(project: project, created_by: admin, creditor_name: "顺序审核债权人", claim_amount: 80_000, currency: "CNY", claimed_type: "ordinary", status: "received")

    post review_claim_path(claim), params: { stage: "principal", decision: "approve", comment: "试图跳级" }
    expect(claim.reload.review_stage).to eq("initial")
    expect(claim.claim_reviews).to be_empty

    verify_claim_materials(claim)
    ClaimReviewFlow::STAGES.each_with_index do |stage, index|
      post review_claim_path(claim), params: { stage: stage, decision: "approve", comment: "第 #{index + 1} 级已核验来源材料" }
      claim.reload
      expect(claim.status).to eq(index == ClaimReviewFlow::STAGES.length - 1 ? "approved" : "pending_approval")
    end

    expect(claim.claim_reviews.order(:id).pluck(:stage)).to eq(ClaimReviewFlow::STAGES)
    expect(claim.status).to eq("approved")
  end
end

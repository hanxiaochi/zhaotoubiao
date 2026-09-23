require "rails_helper"

RSpec.describe "债权历史审核版本保护", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:claim) { project.claims.create!(created_by: admin, creditor_name: "版本验收", claim_amount: 100) }
  before do
    verify_claim_materials(claim)
    sign_in(admin)
    post review_claim_path(claim), params: { stage: "initial", decision: "approve", comment: "核验第一版" }
  end

  it "每次审核保存原始金额、材料与来源摘要，普通申报变更退回初审且不篡改旧快照" do
    review = claim.claim_reviews.first!
    expect(review.basis_sha256).to be_present
    expect(review.evidence_snapshot.fetch("claim").fetch("claim_amount").to_d).to eq(100)
    patch claim_path(claim), params: { claim: { claim_amount: 200 } }
    expect(claim.reload.review_stage).to eq("initial")
    expect(claim.claim_reviews.count).to eq(1)
    expect(review.reload.evidence_snapshot.fetch("claim").fetch("claim_amount").to_d).to eq(100)
    expect(AuditEvent.where(action: "claim.review_restarted")).to exist
    get claim_path(claim)
    expect(response.body).to include("查看本次审核依据快照")
  end

  it "普通材料修改重启审核，未改变的申报保存不清除进度" do
    patch claim_path(claim), params: { claim: { creditor_name: claim.creditor_name } }
    expect(claim.reload.review_stage).to eq("professional")
    material = claim.claim_materials.first!
    patch claim_claim_material_path(claim, material), params: { claim_material: { page_reference: "第2页" } }
    expect(claim.reload.review_stage).to eq("initial")
  end

  it "专业层主动要求的补正保留返回原层级规则，新审核另存新证据且旧审核只读" do
    post review_claim_path(claim), params: { stage: "professional", decision: "request_supplement", comment: "请补充金额说明" }
    patch claim_path(claim), params: { claim: { summary: "已补充说明" } }
    expect(claim.reload.review_stage).to eq("professional")
    post resubmit_claim_path(claim), params: { note: "补正完成" }
    post review_claim_path(claim), params: { stage: "professional", decision: "approve", comment: "补正复核通过" }
    expect(claim.reload.review_stage).to eq("project_manager")
    review = claim.claim_reviews.first!
    expect(review.update(comment: "试图改历史")).to be(false)
    expect(review.reload.destroy).to be(false)
    expect(claim.claim_reviews.count).to eq(3)
  end
end

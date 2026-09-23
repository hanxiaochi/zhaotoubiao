require "rails_helper"

RSpec.describe "债权补正闭环", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:claim) { project.claims.create!(created_by: admin, creditor_name: "补正验收", claim_amount: 100, review_stage: "professional") }
  before { sign_in(admin) }

  it "保存材料快照，补正返回原层级，防止未提交直接审批" do
    material = claim.claim_materials.create!(material_type: "合同", present: false, seal_detected: false)
    post review_claim_path(claim), params: { stage: "professional", decision: "request_supplement", comment: "补合同" }
    expect(claim.reload.status).to eq("supplement_required")
    expect(admin.notifications.where(kind: "claim.review", title: "债权资料需要补正")).to exist
    get claim_path(claim)
    expect(response.body).to include("合同：尚未收到材料", "合同：盖章核验未通过")
    expect do
      post review_claim_path(claim), params: { stage: "professional", decision: "approve", comment: "跳过补正" }
    end.not_to change(ClaimReview, :count)
    patch claim_claim_material_path(claim, material), params: { claim_material: { present: true, seal_detected: true } }
    verify_claim_materials(claim)
    post resubmit_claim_path(claim), params: { note: "已提交盖章合同" }
    expect(claim.reload.status).to eq("pending_approval")
    expect(claim.review_stage).to eq("professional")
    expect(admin.notifications.where(kind: "claim.review", title: "债权待您复核")).to exist
    expect(claim.claim_supplements.last.material_snapshot.first["present"]).to eq(true)
    expect do
      post resubmit_claim_path(claim), params: { note: "重复" }
    end.not_to change(ClaimSupplement, :count)
    post review_claim_path(claim), params: { stage: "professional", decision: "approve", comment: "复核通过" }
    expect(claim.reload.review_stage).to eq("project_manager")
  end

  it "空白补正不能变更状态，终审后不能修改原始申报" do
    claim.update!(status: "supplement_required")
    post resubmit_claim_path(claim), params: { note: " " }
    expect(claim.reload.status).to eq("supplement_required")
    expect(claim.claim_supplements).to be_empty
    claim.update!(status: "approved", review_stage: "principal")
    patch claim_path(claim), params: { claim: { claim_amount: 999 } }
    expect(claim.reload.claim_amount).to eq(100)
  end
end

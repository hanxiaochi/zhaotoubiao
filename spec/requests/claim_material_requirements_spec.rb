require "rails_helper"

RSpec.describe "债权材料适用规则与人工核验门禁", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:claim) { project.claims.create!(created_by: admin, creditor_name: "材料规则验收", claim_amount: 100) }
  before { sign_in(admin) }

  def approve
    post review_claim_path(claim), params: { stage: claim.reload.review_stage, decision: "approve", comment: "人工复核" }
  end

  it "无材料清单不允许通过，已收齐100%也不能替代适用规则和人工核验" do
    expect { approve }.not_to change(ClaimReview, :count)
    material = claim.claim_materials.create!(material_type: "合同", present: true)
    claim.recalculate_completeness!
    expect(claim.reload.completeness_score).to eq(100)
    expect { approve }.not_to change(ClaimReview, :count)
    expect(material.review_issues).to include("来源原件未关联", "尚未人工核验", "签字适用规则尚未确认")
    get claim_path(claim)
    expect(response.body).to include("材料收齐度（不含签章核验）", "合同：来源原件未关联")
  end

  it "明确必需的签字盖章授权必须逐一人工核验，nil与false都不能放行" do
    verify_claim_materials(claim)
    material = claim.claim_materials.first!
    %i[signature_detected seal_detected authorization_complete].each do |field|
      [ nil, false ].each do |value|
        material.update!(field => value)
        expect { approve }.not_to change(ClaimReview, :count)
      end
      material.update!(field => true)
    end
    approve
    expect(claim.reload.review_stage).to eq("professional")
  end

  it "不适用需保留依据，未填写不能保存，明确豁免后不要求该项结果" do
    verify_claim_materials(claim)
    material = claim.claim_materials.first!
    patch claim_claim_material_path(claim, material), params: { claim_material: { seal_requirement: "not_required", seal_detected: nil } }
    expect(material.reload.seal_requirement).to eq("required")
    patch claim_claim_material_path(claim, material), params: { claim_material: { seal_requirement: "not_required", seal_detected: nil, requirement_note: "合成自然人借据，按本案清单无需单位印章" } }
    expect(material.reload.seal_requirement).to eq("not_required")
    expect(material.review_issues).to be_empty
    approve
    expect(claim.reload.review_stage).to eq("professional")
  end

  it "不适用材料不计入收齐度，其余材料仍需通过核验" do
    verify_claim_materials(claim)
    claim.claim_materials.create!(material_type: "不适用附件", material_requirement: "not_required", requirement_note: "本案不涉及该附件")
    claim.recalculate_completeness!
    expect(claim.reload.completeness_score).to eq(100)
    expect(claim.supplement_issues).to be_empty
  end

  it "归档来源让原先通过的材料失效" do
    verify_claim_materials(claim)
    material = claim.claim_materials.first!
    material.project_document.update!(status: "archived")
    expect { approve }.not_to change(ClaimReview, :count)
    expect(material.reload.review_issues).to include("来源文件已归档")
  end

  it "跨项目来源、观察者修改以及终审后修改均被拒绝" do
    verify_claim_materials(claim)
    material = claim.claim_materials.first!
    other = create_project(owner: admin, code: "OTHER-MATERIAL")
    other_claim = other.claims.create!(created_by: admin, creditor_name: "其他案件", claim_amount: 200)
    verify_claim_materials(other_claim)
    original_source = material.project_document_id
    patch claim_claim_material_path(claim, material), params: { claim_material: { project_document_id: other_claim.claim_materials.first!.project_document_id } }
    expect(material.reload.project_document_id).to eq(original_source)
    observer = create_user(email: "material-observer@example.test")
    project.project_memberships.create!(user: observer, membership_role: "observer")
    delete session_path
    sign_in(observer)
    patch claim_claim_material_path(claim, material), params: { claim_material: { note: "非法核验" } }
    expect(material.reload.note).not_to eq("非法核验")
    get claim_path(claim)
    expect(response.body).not_to include('value="保存核验"')
    delete session_path
    sign_in(admin)
    claim.update!(status: "approved", review_stage: "principal")
    patch claim_claim_material_path(claim, material), params: { claim_material: { note: "终审后修改" } }
    expect(material.reload.note).not_to eq("终审后修改")
  end

  it "修改适用规则使已完成会签失效，不允许沿用旧签署" do
    verify_claim_materials(claim)
    post project_workflow_tasks_path(project), params: { workflow_task: { stage: "规则会签", record_ref: "Claim:#{claim.public_id}", signer_ids: [ admin.id ] } }
    task = project.workflow_tasks.last!
    post decide_workflow_task_path(task), params: { decision: "approve", comment: "已核验" }
    material = claim.claim_materials.first!
    patch claim_claim_material_path(claim, material), params: { claim_material: { seal_requirement: "not_required", requirement_note: "适用范围已调整" } }
    expect(task.reload.claim_basis_current?).to be(false)
    expect { approve }.not_to change(ClaimReview, :count)
  end
end

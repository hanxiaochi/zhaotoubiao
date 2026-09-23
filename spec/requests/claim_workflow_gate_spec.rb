require "rails_helper"

RSpec.describe "债权四级审核与前置会签联动", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:member) { create_user(email: "claim-signer@example.test") }
  let!(:project) { create_project(owner: admin) }
  let!(:claim) { project.claims.create!(created_by: admin, creditor_name: "合成债权", claim_amount: 100) }
  before do
    project.project_memberships.create!(user: member, membership_role: "member")
    verify_claim_materials(claim)
    sign_in(admin)
  end

  def assign_task(signers: [ admin.id, member.id ])
    post project_workflow_tasks_path(project), params: { workflow_task: { stage: "合成联合复核", record_ref: "Claim:#{claim.public_id}", signer_ids: signers } }
    project.workflow_tasks.last!
  end

  def as(user)
    delete session_path
    sign_in(user)
  end

  def sign(task, user, decision: "approve")
    as(user)
    post decide_workflow_task_path(task), params: { decision: decision, comment: "合成独立核验：#{decision}" }
  end

  def advance(stage = claim.reload.review_stage)
    as(admin)
    post review_claim_path(claim), params: { stage: stage, decision: "approve", comment: "合成层级审核" }
  end

  it "绑定当前层级，所有人通过后仍需本层人员明确推进" do
    task = assign_task
    expect(task.claim_review_stage).to eq("initial")
    expect(task.claim_basis_sha256).to be_present
    expect { advance }.not_to change(ClaimReview, :count)
    sign(task, admin)
    expect(task.reload.status).to eq("active")
    expect { advance }.not_to change(ClaimReview, :count)
    sign(task, member)
    expect(task.reload.status).to eq("approved")
    expect(claim.reload.review_stage).to eq("initial")
    advance
    expect(claim.reload.review_stage).to eq("professional")
    expect(claim.claim_reviews.count).to eq(1)
    expect(claim.status).not_to eq("approved")
    get claim_path(claim)
    expect(response.body).to include("当前层级前置审批 / 会签")
  end

  it "全部并行前置任务必须通过，不能只完成其中一个" do
    first = assign_task(signers: [ admin.id ])
    second = assign_task(signers: [ admin.id ])
    sign(first, admin)
    expect { advance }.not_to change(ClaimReview, :count)
    sign(second, admin)
    advance
    expect(claim.reload.review_stage).to eq("professional")
  end

  it "有人退回后不能续签或直接过审，新一轮完整保留原人员" do
    task = assign_task
    sign(task, admin, decision: "return")
    sign(task, member)
    expect(task.reload.status).to eq("returned")
    expect(task.workflow_events.count).to eq(1)
    expect { advance }.not_to change(ClaimReview, :count)
    post restart_workflow_task_path(task), params: { restart_reason: "核对补充依据后重新签署", signer_ids: [ admin.id ] }
    replacement = task.reload.replacement_task
    expect(replacement).to be_present
    expect(replacement.workflow_signatures.pluck(:user_id)).to match_array([ admin.id, member.id ])
    expect(replacement.workflow_signatures.pluck(:status).uniq).to eq([ "pending" ])
    expect(task.status).to eq("returned")
    expect(task.workflow_events.count).to eq(1)
    expect { post restart_workflow_task_path(task), params: { restart_reason: "重复提交" } }.not_to change(WorkflowTask, :count)
    sign(replacement, admin)
    sign(replacement, member)
    advance
    expect(claim.reload.review_stage).to eq("professional")
    expect(AuditEvent.where(action: "workflow_task.restart")).to exist
  end

  it "完成会签后修改申报或材料，旧结果不能继续用于过审" do
    material = claim.claim_materials.create!(material_type: "合同", present: true)
    verify_claim_materials(claim)
    task = assign_task(signers: [ admin.id ])
    sign(task, admin)
    patch claim_claim_material_path(claim, material), params: { claim_material: { note: "材料核对意见更新" } }
    expect { advance }.not_to change(ClaimReview, :count)
    expect(task.reload.claim_basis_current?).to be(false)
    post restart_workflow_task_path(task), params: { restart_reason: "材料变化，需要重新确认" }
    replacement = task.reload.replacement_task
    expect(replacement.claim_basis_current?).to be(true)
    sign(replacement, admin)
    advance
    expect(claim.reload.review_stage).to eq("professional")
  end

  it "补正重提使原签署失效，并禁止补正期间创建或办理会签" do
    task = assign_task(signers: [ admin.id ])
    sign(task, admin)
    post review_claim_path(claim), params: { stage: "initial", decision: "request_supplement", comment: "补资料" }
    expect(claim.reload.status).to eq("supplement_required")
    expect { assign_task }.not_to change(WorkflowTask, :count)
    expect(response).to have_http_status(:unprocessable_content)
    post resubmit_claim_path(claim), params: { note: "补正说明已整理" }
    expect(claim.reload.status).to eq("pending_approval")
    expect { advance }.not_to change(ClaimReview, :count)
    expect(task.reload.restartable?).to be(true)
  end

  it "待签期间材料变化时拒绝签署，重发后旧轮次退出个人待办" do
    task = assign_task
    claim.update!(summary: "合成申报事实更新")
    expect { sign(task, member) }.not_to change(WorkflowSignature.where(status: "approved"), :count)
    as(admin)
    post restart_workflow_task_path(task), params: { restart_reason: "重新核对事实" }
    replacement = task.reload.replacement_task
    expect(WorkflowTask.pending_for(member, projects: ProjectPolicy::Scope.new(member, Project).resolve)).to include(replacement)
    expect(WorkflowTask.pending_for(member, projects: ProjectPolicy::Scope.new(member, Project).resolve)).not_to include(task)
    get workflow_task_path(task)
    expect(response.body).to include("本轮已被新一轮替代")
  end

  it "不能任意重启有效待签任务，空原因或失效人员导致整个重发回滚" do
    task = assign_task
    expect { post restart_workflow_task_path(task), params: { restart_reason: "试图清除签署" } }.not_to change(WorkflowTask, :count)
    sign(task, admin, decision: "reject")
    expect { post restart_workflow_task_path(task), params: { restart_reason: " " } }.not_to change(WorkflowTask, :count)
    member.update!(status: "disabled")
    expect { post restart_workflow_task_path(task), params: { restart_reason: "不能忽略停用签署人" } }.not_to change(WorkflowTask, :count)
    expect(task.reload.replacement_task).to be_nil
  end

  it "跨项目管理权限、撤权人和观察者不能推进，终审不能新建任务" do
    task = assign_task
    manager = create_user(email: "outside-gate@example.test", permissions: [ "projects.manage", "claims.review" ])
    as(manager)
    expect { post restart_workflow_task_path(task), params: { restart_reason: "越界" } }.not_to change(WorkflowTask, :count)
    get workflow_tasks_path
    expect(response.body).not_to include("合成联合复核")
    project.project_memberships.find_by!(user: member).destroy!
    as(member)
    get workflow_tasks_path
    expect(response.body).not_to include("合成联合复核")
    expect { sign(task, member) }.not_to change(WorkflowEvent, :count)
    as(admin)
    claim.update!(status: "approved", review_stage: "principal")
    expect { assign_task }.not_to change(WorkflowTask, :count)
  end
end

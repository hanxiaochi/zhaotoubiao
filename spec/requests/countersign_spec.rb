require "rails_helper"

RSpec.describe "多人会签", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:member) { create_user(email: "signer@example.test") }
  let!(:project) { create_project(owner: admin) }
  before do
    project.project_memberships.create!(user: member, membership_role: "member")
    sign_in(admin)
  end

  def create_countersign
    post project_workflow_tasks_path(project), params: { workflow_task: { stage: "联合复核", record_ref: "Project:#{project.public_id}", signer_ids: [ admin.id, member.id ] } }
    project.workflow_tasks.last!
  end

  it "所有会签人通过才完成，已签人员不能重复处理" do
    task = create_countersign
    expect(task.workflow_signatures.count).to eq(2)
    expect(Notification.where(kind: "workflow.assigned").count).to eq(2)
    post decide_workflow_task_path(task), params: { decision: "approve", comment: "第一人核验通过" }
    expect(task.reload.status).to eq("active")
    expect do
      post decide_workflow_task_path(task), params: { decision: "complete", comment: "重复签署" }
    end.not_to change(WorkflowEvent, :count)
    delete session_path
    sign_in(member)
    post decide_workflow_task_path(task), params: { decision: "approve", comment: "第二人独立核验通过" }
    expect(task.reload.status).to eq("approved")
    expect(task.completed_at).to be_present
    get workflow_task_path(task)
    expect(response.body).to include("多人会签进度", "第二人独立核验通过")
  end

  it "任一退回停止本轮，其他成员不能覆盖退回" do
    task = create_countersign
    post decide_workflow_task_path(task), params: { decision: "return", comment: "补证后重新发起" }
    delete session_path
    sign_in(member)
    post decide_workflow_task_path(task), params: { decision: "approve", comment: "试图继续" }
    expect(task.reload.status).to eq("returned")
    expect(task.workflow_events.count).to eq(1)
  end

  it "阻止跨项目人员进入会签，创建失败不留下任务或通知" do
    outsider = create_user(email: "external@example.test")
    expect do
      post project_workflow_tasks_path(project), params: { workflow_task: { stage: "错误会签", record_ref: "Project:#{project.public_id}", signer_ids: [ outsider.id ] } }
    end.not_to change(WorkflowTask, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(Notification.count).to eq(0)
  end
end

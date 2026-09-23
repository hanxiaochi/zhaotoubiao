require "rails_helper"

RSpec.describe "通用审批工作流", type: :request do
  let!(:admin) { create_user(name: "项目负责人", email: "workflow-admin@example.com", admin: true) }
  let!(:member) { create_user(name: "复核人员", email: "workflow-member@example.com") }
  let!(:project) { create_project(owner: admin, code: "WF-001", name: "审批测试项目") }

  before do
    ProjectMembership.create!(project: project, user: member, membership_role: "member")
    sign_in(admin)
  end

  it "创建任务、通知处理人并记录不可丢失的处理轨迹" do
    expect do
      post project_workflow_tasks_path(project), params: { workflow_task: { record_ref: "Project:#{project.public_id}", stage: "合伙人复核", assignee_id: member.id, due_at: 2.days.from_now } }
    end.to change(WorkflowTask, :count).by(1).and change(Notification, :count).by(1)
    task = WorkflowTask.last
    expect(task.record).to eq(project)
    expect(task.assignee).to eq(member)
    expect(Notification.last.user).to eq(member)

    delete session_path
    sign_in(member)

    get workflow_task_path(task)
    expect(response).to have_http_status(:ok)

    expect do
      post decide_workflow_task_path(task), params: { decision: "approve", comment: "已核对底稿和证据索引，同意通过。" }
    end.to change(WorkflowEvent, :count).by(1)
    expect(task.reload.status).to eq("approved")
    expect(task.completed_at).to be_present
    expect(task.workflow_events.last.actor).to eq(member)
    expect(AuditEvent.where(action: "workflow_task.decide", record_id: task.id)).to exist
  end
end

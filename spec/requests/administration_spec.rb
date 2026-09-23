require "rails_helper"

RSpec.describe "用户、角色与项目成员管理", type: :request do
  let!(:admin) { create_user(name: "管理员", email: "admin-users@example.com", admin: true) }

  before { sign_in(admin) }

  it "创建部门、角色和用户并分配权限" do
    post departments_path, params: { department: { code: "qa", name: "质量管理部", active: true } }
    department = Department.find_by!(code: "qa")

    post roles_path, params: { role: { code: "reviewer", name: "复核人员", permissions: [ "claims.review", "audit.view", "unknown.permission" ] } }
    role = Role.find_by!(code: "reviewer")
    expect(role.permissions).to contain_exactly("claims.review", "audit.view")

    post users_path, params: { user: { name: "新员工", email: "new-user@example.com", department_id: department.id, status: "active", password: AuthenticationHelpers::TEST_PASSWORD, password_confirmation: AuthenticationHelpers::TEST_PASSWORD, role_ids: [ role.id ] } }
    user = User.find_by!(email: "new-user@example.com")
    expect(user.department).to eq(department)
    expect(user.roles).to contain_exactly(role)
    expect(AuditEvent.where(action: "user.create", record_id: user.id)).to exist
  end

  it "添加项目成员后授予访问并生成通知" do
    member = create_user(name: "成员", email: "assigned@example.com")
    project = create_project(owner: admin, code: "TEAM-001", name: "团队项目")

    expect do
      post project_project_memberships_path(project), params: { project_membership: { user_id: member.id, membership_role: "member" } }
    end.to change(ProjectMembership, :count).by(1).and change(Notification, :count).by(1)

    expect(ProjectPolicy::Scope.new(member, Project).resolve).to include(project)
    expect(Notification.last.user).to eq(member)
  end

  it "阻止移除项目负责人" do
    project = create_project(owner: admin, code: "TEAM-002", name: "负责人保护")
    membership = project.project_memberships.find_by!(user: admin)

    expect do
      delete project_project_membership_path(project, membership)
    end.not_to change(ProjectMembership, :count)
    expect(response).to redirect_to(project_path(project))
  end
end

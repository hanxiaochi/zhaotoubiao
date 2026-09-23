module AuthenticationHelpers
  TEST_PASSWORD = "SecurePass!2026".freeze

  def create_user(name: "测试用户", email: "user@example.com", admin: false, permissions: [])
    user = User.create!(name: name, email: email, password: TEST_PASSWORD, password_confirmation: TEST_PASSWORD, status: "active")
    if admin
      role = Role.find_or_create_by!(code: "admin") { |item| item.name = "系统管理员"; item.permissions = [ "*" ] }
      user.roles << role
    elsif permissions.any?
      role = Role.create!(code: "role-#{SecureRandom.hex(4)}", name: "测试角色", permissions: permissions)
      user.roles << role
    end
    user
  end

  def sign_in(user)
    post session_path, params: { email: user.email, password: TEST_PASSWORD }
    expect(response).to redirect_to(root_path)
  end

  def create_project(owner:, code: "PRJ-001", name: "测试项目")
    project = Project.create!(code: code, name: name, project_type: "bankruptcy", status: "active", owner: owner, start_date: Date.current)
    ProjectMembership.create!(project: project, user: owner, membership_role: "owner")
    project
  end
end

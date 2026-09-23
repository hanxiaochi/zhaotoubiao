require "rails_helper"

RSpec.describe "角色权限更新语义", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:role) { Role.create!(code: "permission-update", name: "合成审核角色", permissions: [ "audit.view", "claims.review" ]) }
  before { sign_in(admin) }

  it "只修改名称不擦除未提交的权限，并留下原有权限的审计快照" do
    patch role_path(role), params: { role: { name: "更名后角色" } }
    expect(response).to redirect_to(roles_path)
    expect(role.reload.name).to eq("更名后角色")
    expect(role.permissions).to eq([ "audit.view", "claims.review" ])
    event = AuditEvent.where(action: "role.update", record_type: "Role", record_id: role.id).last!
    expect(event.before_data.fetch("permissions")).to eq(role.permissions)
    expect(event.after_data.fetch("permissions")).to eq(role.permissions)
  end

  it "全不勾选有明确的空数组表单值，提交后撤销权限而不是保留" do
    get edit_role_path(role)
    form = Nokogiri::HTML(response.body)
    expect(form.at_css('input[type="hidden"][name="role[permissions][]"][value=""]')).to be_present
    member = create_user(email: "permission-member@example.test")
    member.roles << role
    patch role_path(role), params: { role: { permissions: [ "" ] } }
    expect(response).to redirect_to(roles_path)
    expect(role.reload.permissions).to eq([])
    expect(member.reload.allowed?("audit.view")).to be(false)
  end

  it "只保存白名单权限并拒绝普通成员改角色" do
    patch role_path(role), params: { role: { permissions: [ "", "audit.view", "*", "unrecognized" ] } }
    expect(response).to redirect_to(roles_path)
    expect(role.reload.permissions).to eq([ "audit.view" ])
    member = create_user(email: "unauthorized-role@example.test")
    sign_in(member)
    expect do
      patch role_path(role), params: { role: { permissions: [ "claims.review" ] } }
    end.not_to change { AuditEvent.where(action: "role.update").count }
    expect(response).to have_http_status(:redirect)
    expect(role.reload.permissions).to eq([ "audit.view" ])
  end

  it "管理员内置角色仍不能经通用角色接口修改" do
    built_in = Role.find_by!(code: "admin")
    patch role_path(built_in), params: { role: { code: "renamed", permissions: [ "" ] } }
    expect(response).to have_http_status(:redirect)
    expect(built_in.reload.code).to eq("admin")
    expect(admin.reload.admin?).to be(true)
  end
end

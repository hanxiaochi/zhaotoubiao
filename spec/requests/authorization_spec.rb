require "rails_helper"

RSpec.describe "项目权限隔离", type: :request do
  let!(:admin) { create_user(name: "管理员", email: "admin@example.com", admin: true) }
  let!(:member) { create_user(name: "项目成员", email: "member@example.com") }
  let!(:allowed_project) { create_project(owner: admin, code: "AUTH-001", name: "可访问项目") }
  let!(:blocked_project) { create_project(owner: admin, code: "AUTH-002", name: "隔离项目") }

  before do
    ProjectMembership.create!(project: allowed_project, user: member, membership_role: "member")
    sign_in(member)
  end

  it "成员只能看到已分配项目" do
    get projects_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("可访问项目")
    expect(response.body).not_to include("隔离项目")

    get project_path(allowed_project)
    expect(response).to have_http_status(:ok)

    get project_path(blocked_project)
    expect(response).to redirect_to(root_path)
  end

  it "普通成员不能创建项目或读取审计日志" do
    get root_path
    expect(response.body).not_to include(new_project_path)
    get projects_path
    expect(response.body).not_to include(new_project_path)
    get new_project_path
    expect(response).to redirect_to(root_path)

    get audit_events_path
    expect(response).to redirect_to(root_path)
  end

  it "观察者项目页不显示写入入口，台账和文件读取入口仍可用" do
    allowed_project.project_memberships.find_by!(user: member).update!(membership_role: "observer")
    get project_path(allowed_project)
    expect(response).to have_http_status(:ok)
    [ edit_project_path(allowed_project), new_project_asset_path(allowed_project), new_project_claim_path(allowed_project),
      new_project_intake_item_path(allowed_project), new_project_project_document_path(allowed_project),
      new_project_bid_analysis_path(allowed_project), new_project_generated_document_path(allowed_project),
      new_project_workflow_task_path(allowed_project) ].each do |path|
      expect(response.body).not_to include(path)
    end
    expect(response.body).to include(ledger_project_path(allowed_project, kind: "assets"))
  end

  it "负责人同时是成员时不重复列出且保留 JSON 元数据" do
    allowed_project.update!(owner: member, metadata: { "scope_test" => "preserved" })
    scope = ProjectPolicy::Scope.new(member, Project).resolve
    expect(scope.to_a.map(&:id)).to eq([ allowed_project.id ])
    expect(scope.first.metadata).to eq("scope_test" => "preserved")
    get projects_path
    expect(response).to have_http_status(:ok)
  end
end

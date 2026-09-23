require "rails_helper"

RSpec.describe "接管原件只读详情", type: :request do
  it "观察者从台账查看详情和受控附件但不能编辑，跨项目不能访问" do
    owner = create_user(admin: true)
    observer = create_user(email: "intake-observer@example.test")
    project = create_project(owner: owner)
    project.project_memberships.create!(user: observer, membership_role: "observer")
    item = project.intake_items.create!(created_by: owner, category: "合同", name: "合成接管详情", status: "received", custodian: "合成保管人")
    sign_in(observer)
    get ledger_project_path(project, kind: "intake")
    expect(response.body).to include(project_intake_item_path(project, item))
    get project_intake_item_path(project, item)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("合成保管人", "尚未上传附件")
    expect(response.body).not_to include("维护资料")
    get edit_project_intake_item_path(project, item)
    expect(response).to redirect_to(root_path)
    project.project_memberships.find_by!(user: observer).destroy!
    get project_intake_item_path(project, item)
    expect(response).to redirect_to(root_path)
  end
end

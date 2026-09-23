require "rails_helper"

RSpec.describe "招标模板查找与停用保护", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:template) { TenderTemplate.create!(created_by: admin, name: "服务公开模板", project_category: "服务", tender_method: "公开招标", body: "项目【项目名称】；甲方【甲方名称】", active: true) }
  let!(:project) { create_project(owner: admin).tap { |item| item.update!(project_type: "tender_agency", client_name: "合成甲方") } }
  before { sign_in(admin) }

  it "按类别和方式查模板并将真实项目字段带入草稿，未知或停用模板不能生成" do
    get tender_templates_path(category: "服务", method: "公开招标", q: "公开")
    expect(response.body).to include(template.name, "共 1 项")
    get tender_templates_path(category: "工程")
    expect(response.body).to include("共 0 项")
    expect(response.body).not_to include(template.name)
    get new_project_generated_document_path(project, template_id: template.public_id, kind: "tender_document")
    expect(response.body).to include("合成甲方", project.name)
    template.update!(active: false)
    get tender_template_path(template)
    expect(response.body).to include("模板已停用")
    expect(response.body).not_to include("template_id=#{template.public_id}")
    get new_project_generated_document_path(project, template_id: template.public_id)
    expect(response).to have_http_status(:not_found)
    get new_project_generated_document_path(project, template_id: "missing-template")
    expect(response).to have_http_status(:not_found)
  end

  it "超过首批项目仍可通过分页及编号搜索生成，不仅限最近12项" do
    31.times { |index| create_project(owner: admin, code: "TEMPLATE-P#{index}").update!(project_type: "tender_agency") }
    get tender_template_path(template, page: 2)
    expect(response.body).to include("共 32 项", "上一页", project.code)
    get tender_template_path(template, q: project.code)
    expect(response.body).to include("共 1 项", "template_id=#{template.public_id}")
    get tender_template_path(template, q: "nothing-matches")
    expect(response.body).to include("共 0 项")
  end

  it "只读项目成员不看到无法使用的生成入口" do
    reader = create_user(email: "template-readonly@example.test")
    ProjectMembership.create!(project: project, user: reader, membership_role: "observer")
    delete session_path
    sign_in(reader)
    get tender_template_path(template)
    expect(response.body).to include("共 0 项")
    expect(response.body).not_to include("template_id=#{template.public_id}")
    get new_project_generated_document_path(project, template_id: template.public_id)
    expect(response).to redirect_to(root_path)
  end
end

require "rails_helper"

RSpec.describe Tender::TemplateRenderer do
  include AuthenticationHelpers

  it "用项目和模板数据替换受控占位符并保留待补提示" do
    user = create_user(email: "template-render@example.com")
    project = create_project(owner: user, code: "TENDER-RENDER", name: "审计服务采购")
    project.update!(client_name: "江苏示例集团", project_category: "服务", tender_method: "公开招标", budget_amount: "500000")
    template = TenderTemplate.create!(name: "服务模板", project_category: "服务", tender_method: "邀请招标", body: "【甲方名称】就【项目名称】采用【招标方式】，预算【项目预算】，截止【截止日期】。", created_by: user)

    result = described_class.call(template: template, project: project)

    expect(result).to include("江苏示例集团", "审计服务采购", "公开招标", "500000")
    expect(result).to include("【待填写截止日期】")
  end
end

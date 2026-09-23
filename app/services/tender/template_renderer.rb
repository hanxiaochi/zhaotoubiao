module Tender
  class TemplateRenderer
    PLACEHOLDERS = {
      "【项目名称】" => ->(project, template) { project.name },
      "【项目编号】" => ->(project, template) { project.code },
      "【项目类别】" => ->(project, template) { project.project_category.presence || template.project_category },
      "【招标方式】" => ->(project, template) { project.tender_method.presence || template.tender_method },
      "【甲方名称】" => ->(project, _template) { project.client_name.presence || "【待填写甲方名称】" },
      "【项目预算】" => ->(project, _template) { project.budget_amount.present? ? project.budget_amount.to_s : "【待填写项目预算】" },
      "【项目说明】" => ->(project, _template) { project.description.presence || "【待填写项目说明】" },
      "【开始日期】" => ->(project, _template) { project.start_date&.to_s || "【待填写开始日期】" },
      "【截止日期】" => ->(project, _template) { project.due_date&.to_s || "【待填写截止日期】" }
    }.freeze

    def self.call(template:, project:)
      PLACEHOLDERS.reduce(template.body.dup) do |content, (placeholder, resolver)|
        content.gsub(placeholder, resolver.call(project, template))
      end
    end
  end
end

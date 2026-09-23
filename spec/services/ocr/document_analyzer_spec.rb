require "rails_helper"

RSpec.describe Ocr::DocumentAnalyzer do
  it "提取材料候选分类、债权字段和页码来源" do
    text = <<~TEXT
      债权申报书
      债权人：江苏示例科技有限公司
      统一社会信用代码：91320000MA1234567X
      联系电话：13812345678
      申报债权金额：人民币 1,234.56
    TEXT

    result = described_class.call(text: text, pages: [ { "page" => 1, "text" => text } ])

    expect(result["classification"]).to eq("债权申报书")
    expect(result["classification_confidence"]).to be_between(1, 100)
    expect(result.dig("extracted_fields", "creditor_name")).to eq("江苏示例科技有限公司")
    expect(result.dig("extracted_fields", "unified_code")).to eq("91320000MA1234567X")
    expect(result.dig("extracted_fields", "claim_amount")).to eq("1234.56")
    expect(result.dig("field_sources", "creditor_name", "page")).to eq(1)
    expect(result.dig("field_sources", "claim_amount", "page")).to eq(1)
    expect(result.dig("field_sources", "claim_amount", "snippet")).to include("1,234.56")
  end

  it "资料不足时不伪造分类和字段" do
    result = described_class.call(text: "扫描内容无法识别", pages: [])

    expect(result["classification"]).to be_nil
    expect(result["classification_confidence"]).to eq(0)
    expect(result["extracted_fields"]).to be_empty
  end
end

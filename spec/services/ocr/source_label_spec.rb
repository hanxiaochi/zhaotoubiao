require "rails_helper"

RSpec.describe Ocr::SourceLabel do
  it "区分扫描物理页、Word逻辑文档与Excel工作表，不伪造排版页码" do
    expect(described_class.call({ "page" => 3 })).to eq("第 3 页")
    expect(described_class.call({ "page" => 1, "location_kind" => "logical_document" })).to include("排版页码待核验")
    expect(described_class.call({ "page" => 2, "sheet" => "本金表", "location_kind" => "worksheet" })).to eq("工作表：本金表（非打印页码）")
    expect(described_class.call(nil)).to eq("来源位置待核验")
  end

  it "分析字段和签章线索时保留来源类型，文字线索不升级为人工核验" do
    text = "债权人：合成企业\n申报金额：12345\n签字处"
    result = Ocr::DocumentAnalyzer.call(text: text, pages: [ { "page" => 1, "location_kind" => "logical_document", "text" => text } ])
    expect(result.dig("field_sources", "creditor_name", "location_kind")).to eq("logical_document")
    expect(result.dig("review_indicators", "signature", "location_kind")).to eq("logical_document")
    expect(result.dig("review_indicators", "signature", "basis")).to include("不能用于鉴定")
  end
end

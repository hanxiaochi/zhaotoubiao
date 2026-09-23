require "rails_helper"

RSpec.describe DocumentExport::DocxBuilder do
  include AuthenticationHelpers

  it "生成包含标题、正文和样式的有效 DOCX 包" do
    user = create_user(email: "docx-builder@example.com")
    project = create_project(owner: user, code: "DOCX-001")
    document = GeneratedDocument.create!(project: project, created_by: user, kind: "tender_document", title: "招标文件初稿", content: "第一章 招标公告\n正文内容", status: "draft")

    bytes = described_class.call(document)

    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      expect(zip.map(&:name)).to include("[Content_Types].xml", "word/document.xml", "word/styles.xml", "word/numbering.xml")
      xml = zip.read("word/document.xml").force_encoding(Encoding::UTF_8)
      expect(xml).to include("招标文件初稿", "第一章 招标公告", "正文内容")
    end
  end

  it "将阿拉伯数字条目导出为真正的 Word 编号而非一级标题" do
    document = GeneratedDocument.new(title: "清单", content: "1. 收集资料\n2. 人工复核")

    Zip::File.open_buffer(StringIO.new(described_class.call(document))) do |zip|
      xml = zip.read("word/document.xml").force_encoding(Encoding::UTF_8)
      numbering = zip.read("word/numbering.xml").force_encoding(Encoding::UTF_8)
      content_types = zip.read("[Content_Types].xml").force_encoding(Encoding::UTF_8)
      expect(xml.scan('w:numId w:val="1"').size).to eq(2)
      expect(xml).not_to include(">1. 收集资料<", ">2. 人工复核<")
      expect(numbering).to include('w:numFmt w:val="decimal"')
      expect(content_types).to include("wordprocessingml.numbering+xml")
    end
  end
end

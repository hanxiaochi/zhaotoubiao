require "rails_helper"

RSpec.describe Ocr::DocumentJob, type: :job do
  it "直接提取 UTF-8 文本文件并保存页级元数据" do
    password = "SecurePass!2026"
    user = User.create!(name: "OCR 测试员", email: "ocr-job@example.com", password: password, password_confirmation: password, status: "active")
    project = Project.create!(code: "OCR-001", name: "OCR 测试项目", project_type: "financial_audit", status: "active", owner: user)
    path = Rails.root.join("spec/fixtures/files/evidence.txt")
    document = ProjectDocument.new(
      project: project,
      uploaded_by: user,
      category: "working_paper",
      status: "uploaded",
      original_filename: "evidence.txt",
      content_type: "text/plain",
      byte_size: File.size(path),
      sha256: Digest::SHA256.file(path).hexdigest,
      ocr_status: "queued",
      analysis_status: "queued"
    )
    document.file.attach(io: File.open(path, "rb"), filename: "evidence.txt", content_type: "text/plain")
    document.save!

    described_class.perform_now(document.id)

    expect(document.reload.ocr_status).to eq("completed")
    expect(document.ocr_text).to include("文件上传验收样本")
    expect(document.metadata["ocr_engine"]).to eq("rails-text")
    expect(document.metadata["ocr_pages"]).to be_an(Array)
  end
end

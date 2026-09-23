require "rails_helper"

RSpec.describe "证据原件下载边界", type: :request do
  let!(:owner) { create_user(admin: true) }
  let!(:project) { create_project(owner: owner) }
  let!(:member) { create_user(email: "download-member@example.test") }
  let!(:membership) { ProjectMembership.create!(project: project, user: member, membership_role: "observer") }
  let!(:document) do
    project.project_documents.create!(uploaded_by: owner, category: "contract", original_filename: "proof.txt", content_type: "text/plain",
      file: { io: StringIO.new("private original"), filename: "proof.txt", content_type: "text/plain" })
  end

  it "每次读取检查权限、返回附件且禁止缓存，移除成员后同一地址失效" do
    sign_in(member)
    path = download_project_project_document_path(project, document)
    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("private original")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(AuditEvent.where(action: "document.download", actor: member)).to exist
    membership.destroy!
    get path
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("private original")
    delete session_path
    get path
    expect(response).to redirect_to(new_session_path)
  end

  it "默认 Blob、代理、磁盘和直接上传路由关闭，即使持有真实签名也不能绕过业务鉴权" do
    signed = document.file.blob.signed_id
    [
      "/rails/active_storage/blobs/redirect/#{signed}/proof.txt",
      "/rails/active_storage/blobs/proxy/#{signed}/proof.txt",
      "/rails/active_storage/disk/#{signed}/proof.txt"
    ].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("private original")
    end
    post "/rails/active_storage/direct_uploads", params: { blob: {} }
    expect(response).to have_http_status(:not_found)
  end

  it "接管附件绑定清单与项目，不能跨清单或跨项目读取" do
    item = project.intake_items.create!(created_by: owner, category: "合同", name: "原件接管", status: "received")
    item.attachments.attach(io: StringIO.new("intake proof"), filename: "intake.txt", content_type: "text/plain")
    file = item.attachments.first!
    sign_in(member)
    get download_project_intake_item_path(project, item, attachment_id: file.id)
    expect(response.body).to eq("intake proof")
    expect(response.headers["Cache-Control"]).to include("no-store")
    other_item = project.intake_items.create!(created_by: owner, category: "合同", name: "另一清单", status: "pending")
    get download_project_intake_item_path(project, other_item, attachment_id: file.id)
    expect(response).to have_http_status(:not_found)
    other_project = create_project(owner: owner, code: "OTHER-DL")
    get download_project_intake_item_path(other_project, item, attachment_id: file.id)
    expect(response).to have_http_status(:not_found)
    membership.destroy!
    get download_project_intake_item_path(project, item, attachment_id: file.id)
    expect(response).to have_http_status(:redirect)
  end

  it "接管再次上传为追加，伪装类型失败时保留全部已有原件" do
    sign_in(owner)
    item = project.intake_items.create!(created_by: owner, category: "合同", name: "追加验收", status: "pending")
    item.attachments.attach(io: StringIO.new("first"), filename: "first.txt", content_type: "text/plain")
    second = Rack::Test::UploadedFile.new(StringIO.new("second"), "text/plain", original_filename: "second.txt")
    patch project_intake_item_path(project, item), params: { intake_item: { attachments: [ second ] } }
    expect(response).to redirect_to(project)
    expect(item.reload.attachments.map { |a| a.filename.to_s }).to contain_exactly("first.txt", "second.txt")
    bad = Rack::Test::UploadedFile.new(StringIO.new("<html><script>bad()</script></html>"), "application/pdf", original_filename: "unsafe.html")
    patch project_intake_item_path(project, item), params: { intake_item: { name: "不应保存", attachments: [ bad ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(item.reload.name).to eq("追加验收")
    expect(item.attachments.count).to eq(2)
  end
end

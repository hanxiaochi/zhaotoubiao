require "rails_helper"

RSpec.describe "原件上传进度请求协议", type: :request do
  let!(:owner) { create_user(admin: true) }
  let!(:project) { create_project(owner: owner) }
  before { sign_in(owner) }

  def upload
    fixture_file_upload(Rails.root.join("spec/fixtures/files/evidence.txt"), "text/plain")
  end

  it "浏览器增强上传使用201与站内详情地址，重复文件422且不重复保存" do
    get new_project_project_document_path(project)
    expect(response.body).to include('data-controller="upload"', 'aria-label="已传输百分比"')
    post project_project_documents_path(project), params: { project_document: { category: "claim", file: upload } }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:created)
    document = project.project_documents.last!
    expect(JSON.parse(response.body).fetch("redirect_url")).to eq(project_project_document_path(project, document))
    expect do
      post project_project_documents_path(project), params: { project_document: { category: "claim", file: upload } }, headers: { "Accept" => "application/json" }
    end.not_to change(ProjectDocument, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("errors")).not_to be_empty
  end

  it "未选择文件返回可读错误而非HTML成功页" do
    post project_project_documents_path(project), params: { project_document: { category: "claim" } }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("errors").join).to include("必须选择文件")
    expect(project.project_documents).to be_empty
  end
end

require "rails_helper"

RSpec.describe "招标与投标工作流", type: :request do
  let!(:admin) { create_user(admin: true, email: "tender-admin@example.com") }

  before { sign_in(admin) }

  it "管理招标模板版本和授权数据源" do
    post tender_templates_path, params: { tender_template: { name: "服务采购模板", project_category: "服务", tender_method: "公开招标", body: "第一章 招标公告", active: true } }
    template = TenderTemplate.last
    expect(response).to redirect_to(tender_template_path(template))
    expect(template.revision_number).to eq(1)

    patch tender_template_path(template), params: { tender_template: { name: template.name, project_category: template.project_category, tender_method: template.tender_method, body: "第一章 招标公告\n第二章 评分办法", active: true } }
    expect(template.reload.revision_number).to eq(2)

    post tender_sources_path, params: { tender_source: { name: "授权测试源", base_url: "https://example.test/api", access_mode: "licensed_api", active: false, authorized: false } }
    source = TenderSource.last
    expect(source).not_to be_active

    patch tender_source_path(source), params: { tender_source: { name: source.name, base_url: source.base_url, access_mode: source.access_mode, active: true, authorized: true } }
    expect(source.reload).to be_active
    expect(source).to be_authorized
  end

  it "登记招标信息并保留来源授权约束" do
    source = TenderSource.create!(name: "公开 API", base_url: "https://example.test/notices", access_mode: "public_api", active: true, authorized: true)

    post tender_notices_path, params: { tender_notice: { tender_source_id: source.id, external_id: "EXT-001", title: "会计服务采购项目", url: "https://example.test/notices/1", region: "江苏", industry: "服务", status: "new", published_at: Time.current, deadline_at: 10.days.from_now } }
    notice = TenderNotice.last
    expect(response).to redirect_to(tender_notice_path(notice))
    expect(notice.tender_source).to eq(source)
    expect(AuditEvent.where(action: "tender_notice.create", record_id: notice.id)).to exist

    patch tender_notice_path(notice), params: { tender_notice: { title: notice.title, url: notice.url, status: "tracking" } }
    expect(response).to redirect_to(tender_notice_path(notice))
    expect(notice.reload.status).to eq("tracking")
    expect(AuditEvent.where(action: "tender_notice.update", record_id: notice.id)).to exist
  end

  it "允许招标管理员更新历史停用来源的跟进状态" do
    manager = create_user(email: "tender-manager@example.com", permissions: [ "tenders.manage" ])
    source = TenderSource.create!(name: "历史授权源", base_url: "https://example.test/notices", access_mode: "licensed_api", active: true, authorized: true)
    notice = TenderNotice.create!(tender_source: source, title: "历史公告", url: "https://example.test/notices/old", status: "new")
    source.update!(active: false, authorized: false)
    delete session_path
    sign_in(manager)

    patch tender_notice_path(notice), params: { tender_notice: { title: notice.title, url: notice.url, status: "ignored" } }

    expect(response).to redirect_to(tender_notice_path(notice))
    expect(notice.reload.status).to eq("ignored")
    expect(notice.tender_source).to eq(source)
  end

  it "创建投标分析、人工复核并生成文稿审批轨迹" do
    project = create_project(owner: admin, code: "BID-001", name: "投标测试项目")

    post project_bid_analyses_path(project), params: { bid_analysis: { criteria_text: "技术方案（30分）\n团队能力（20分）", risks_text: "证书有效期需核验", outline_text: "项目理解\n实施方案", simulated_score: 82.5 } }
    analysis = BidAnalysis.last
    expect(analysis.criteria).to eq([ "技术方案（30分）", "团队能力（20分）" ])
    expect(analysis.status).to eq("draft")

    post review_bid_analysis_path(analysis), params: { review_note: "已对照招标文件原文逐项复核。" }
    expect(analysis.reload.status).to eq("reviewed")
    expect(analysis.reviewed_by).to eq(admin)

    post project_generated_documents_path(project), params: { generated_document: { kind: "bid_technical", title: "技术标初稿", content: "一、项目理解\n二、实施方案" } }
    document = GeneratedDocument.last
    expect(document.status).to eq("draft")

    post submit_generated_document_path(document)
    expect(document.reload.status).to eq("pending_review")

    post approve_generated_document_path(document), params: { review_note: "内容已人工审定，可作为内部定稿。" }
    expect(document.reload.status).to eq("approved")
    expect(document.approved_by).to eq(admin)
    expect(AuditEvent.where(action: "generated_document.approve", record_id: document.id)).to exist

    get download_docx_generated_document_path(document)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    Zip::File.open_buffer(StringIO.new(response.body)) do |zip|
      expect(zip.read("word/document.xml").force_encoding(Encoding::UTF_8)).to include("技术标初稿", "项目理解")
    end
    expect(AuditEvent.where(action: "generated_document.download_docx", record_id: document.id)).to exist
  end
end

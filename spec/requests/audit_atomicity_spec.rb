require "rails_helper"

RSpec.describe "全平台审计原子性与管理员保留", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  before { sign_in(admin) }

  def fail_audit(action)
    allow(Audit::Recorder).to receive(:call).and_call_original
    allow(Audit::Recorder).to receive(:call).with(hash_including(action: action)).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))
  end

  it "所有新增基础业务记录在审计失败时一并回滚" do
    cases = [
      [ Department, departments_path, { department: { code: "ATOMIC", name: "合成部门" } }, "department.create" ],
      [ Role, roles_path, { role: { code: "atomic", name: "合成角色", permissions: [ "audit.view" ] } }, "role.create" ],
      [ TenderSource, tender_sources_path, { tender_source: { name: "合成来源", base_url: "https://example.test", access_mode: "manual_import", active: false } }, "tender_source.create" ],
      [ TenderNotice, tender_notices_path, { tender_notice: { title: "合成公告", url: "https://example.test", status: "new" } }, "tender_notice.create" ],
      [ TenderTemplate, tender_templates_path, { tender_template: { name: "合成模板", project_category: "服务", tender_method: "公开招标", body: "合成文本" } }, "tender_template.create" ],
      [ GeneratedDocument, project_generated_documents_path(project), { generated_document: { kind: "general", title: "合成文稿", content: "合成内容" } }, "generated_document.create" ],
      [ IntakeItem, project_intake_items_path(project), { intake_item: { category: "financial", name: "合成接管", status: "pending" } }, "intake.create" ],
      [ ClaimChecklist, project_claim_checklists_path(project), { claim_checklist: { name: "合成清单", claim_type: "unknown", material_types_text: "合同" } }, "claim_checklist.create" ],
      [ ProjectMilestone, project_project_milestones_path(project), { project_milestone: { title: "合成节点", stage: "核对", status: "pending" } }, "project_milestone.create" ]
    ]
    cases.each do |model, path, params, action|
      fail_audit(action)
      expect { post path, params: params }.not_to change(model, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Audit::Recorder).to have_received(:call).with(hash_including(action: action))
    end
  end

  it "项目更新和归档元数据与审计同事务" do
    fail_audit("project.update")
    patch project_path(project), params: { project: { name: "不得保存", status: "archived", archive_reason: "模拟故障" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(project.reload.name).to eq("测试项目")
    expect(project.status).to eq("active")
    expect(project.archived_at).to be_nil
  end

  it "基础配置更新在审计失败时保留旧值" do
    department = Department.create!(code: "ATOMIC", name: "原部门")
    role = Role.create!(code: "atomic", name: "原角色", permissions: [])
    source = TenderSource.create!(name: "原来源", base_url: "https://example.test", access_mode: "manual_import", active: false)
    notice = TenderNotice.create!(title: "原公告", url: "https://example.test", status: "new")
    checklist = project.claim_checklists.create!(created_by: admin, name: "原清单", claim_type: "unknown", material_types: [ "合同" ])
    milestone = project.project_milestones.create!(title: "原节点", stage: "核对", status: "pending")
    cases = [
      [ department, department_path(department), :department, :name, "department.update" ],
      [ role, role_path(role), :role, :name, "role.update" ],
      [ source, tender_source_path(source), :tender_source, :name, "tender_source.update" ],
      [ notice, tender_notice_path(notice), :tender_notice, :title, "tender_notice.update" ],
      [ checklist, project_claim_checklist_path(project, checklist), :claim_checklist, :name, "claim_checklist.update" ],
      [ milestone, project_project_milestone_path(project, milestone), :project_milestone, :title, "project_milestone.update" ]
    ]
    cases.each do |record, path, key, field, action|
      original = record.public_send(field)
      fail_audit(action)
      values = { field => "不得保存" }
      values[:material_types_text] = "合同" if key == :claim_checklist
      patch path, params: { key => values }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Audit::Recorder).to have_received(:call).with(hash_including(action: action))
      expect(record.reload.public_send(field)).to eq(original)
    end
  end

  it "加入成员及站内通知原子回滚，移除审计失败时成员仍存在" do
    member = create_user(email: "atomic-member@example.test")
    fail_audit("project_membership.create")
    before_notifications = Notification.count
    expect do
      post project_project_memberships_path(project), params: { project_membership: { user_id: member.id, membership_role: "member" } }
    end.not_to change(ProjectMembership, :count)
    expect(Notification.count).to eq(before_notifications)
    membership = project.project_memberships.create!(user: member, membership_role: "member")
    fail_audit("project_membership.remove")
    delete project_project_membership_path(project, membership)
    expect(Audit::Recorder).to have_received(:call).with(hash_including(action: "project_membership.remove"))
    expect(response).to have_http_status(:redirect)
    expect(ProjectMembership.exists?(membership.id)).to be(true)
  end

  it "上传审计失败不留下文件记录、附件或blob" do
    fail_audit("document.upload")
    before_counts = [ ProjectDocument.count, ActiveStorage::Attachment.count, ActiveStorage::Blob.count ]
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/evidence.txt"), "text/plain")
    post project_project_documents_path(project), params: { project_document: { category: "claim", file: upload } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Audit::Recorder).to have_received(:call).with(hash_including(action: "document.upload"))
    expect([ ProjectDocument.count, ActiveStorage::Attachment.count, ActiveStorage::Blob.count ]).to eq(before_counts)
  end

  it "最后一个管理员不能自撤角色，局部资料更新不会擦除角色" do
    patch user_path(admin), params: { user: { name: "合成新名称" } }
    expect(response).to have_http_status(:redirect)
    expect(admin.reload.admin?).to be(true)
    patch user_path(admin), params: { user: { role_ids: [ "" ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("必须保留至少一个启用的系统管理员")
    expect(admin.reload.admin?).to be(true)
    get users_path
    expect(response).to have_http_status(:ok)
  end

  it "有其他启用管理员时可撤自身角色，下个请求立即失去管理入口" do
    second = create_user(email: "second-admin@example.test", admin: true)
    patch user_path(admin), params: { user: { role_ids: [ "" ] } }
    expect(response).to have_http_status(:redirect)
    expect(admin.reload.admin?).to be(false)
    expect(second.reload.admin?).to be(true)
    get users_path
    expect(response).to have_http_status(:redirect)
  end
end

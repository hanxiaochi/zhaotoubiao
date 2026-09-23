require "rails_helper"

RSpec.describe "完整收费台账与项目分页", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  before { sign_in(admin) }

  def fee(**attributes)
    project.fees.create!({ created_by: admin, fee_type: "agency", receivable: 100, received: 40, invoice_status: "not_issued", note: "合成首期款" }.merge(attributes))
  end

  it "全部历史收费可分页、组合筛选和只读查看，金额按全部筛选结果汇总" do
    oldest = fee(note: "历史尾款", received: 120, invoice_status: "issued")
    31.times { fee }
    get project_fees_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("共 32 笔", "下一页", "¥3,200.00", "¥1,860.00", "¥20.00")
    get project_fees_path(project, page: 2)
    expect(response.body).to include("上一页", "历史尾款", project_fee_path(project, oldest))
    get project_fees_path(project, q: "尾款", fee_type: "agency", invoice_status: "issued", payment_status: "overpaid")
    expect(response.body).to include("共 1 笔", "历史尾款")
    expect(response.body).not_to include("合成首期款")
    get project_fee_path(project, oldest)
    expect(response.body).to include("历史尾款", "溢收", "¥20.00", "¥0.00")
    expect(oldest.outstanding).to eq(0)
    expect(oldest.overpaid).to eq(20)
    get project_fees_path(project, q: "不存在")
    expect(response.body).to include("共 0 笔", "暂无符合")
  end

  it "只读成员正常查看项目费用，无编辑入口，跨项目与匿名访问被拒绝" do
    item = fee
    reader = create_user(email: "fee-reader@example.test")
    ProjectMembership.create!(project: project, user: reader, membership_role: "observer")
    other_project = create_project(owner: admin, code: "PRIVATE")
    delete session_path
    sign_in(reader)
    get project_path(project)
    expect(response.body).to include(project_fees_path(project), project_fee_path(project, item))
    expect(response.body).not_to include(new_project_fee_path(project), edit_project_fee_path(project, item))
    get project_fees_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(edit_project_fee_path(project, item))
    get project_fee_path(project, item)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("编辑收费")
    patch project_fee_path(project, item), params: { fee: { received: 99 } }
    expect(response).to redirect_to(root_path)
    expect(item.reload.received).to eq(40)
    get project_fees_path(other_project)
    expect(response).to redirect_to(root_path)
    get project_fee_path(other_project, item)
    expect(response).to have_http_status(:not_found)
    delete session_path
    get project_fee_path(project, item)
    expect(response).to redirect_to(new_session_path)
  end

  it "开票状态非法时拒绝保存，正常修改与审计一致" do
    item = fee
    patch project_fee_path(project, item), params: { fee: { received: 80, invoice_status: "invented" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(item.reload.received).to eq(40)
    expect { patch project_fee_path(project, item), params: { fee: { received: 80, invoice_status: "issued" } } }.to change(AuditEvent.where(action: "fee.update"), :count).by(1)
    expect(response).to redirect_to(project_fee_path(project, item))
    expect(item.reload.received).to eq(80)
    event = AuditEvent.find_by!(action: "fee.update", record_id: item.id)
    expect(event.before_data.fetch("received").to_d).to eq(40)
    expect(event.after_data.fetch("received").to_d).to eq(80)
  end

  it "审计失败时收费新增与修改均回滚" do
    item = fee
    allow(Audit::Recorder).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))
    expect { post project_fees_path(project), params: { fee: { fee_type: "agency", receivable: 100, received: 20, invoice_status: "issued" } } }.not_to change(Fee, :count)
    expect(response).to have_http_status(:unprocessable_content)
    patch project_fee_path(project, item), params: { fee: { received: 90 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(item.reload.received).to eq(40)
  end

  it "项目超过30项完整分页且保留组合筛选，非法日期与反向范围明确拒绝" do
    project.update!(due_date: Date.current)
    31.times { |index| create_project(owner: admin, code: "PAGED-#{index}").update!(due_date: Date.current) }
    get projects_path(type: "bankruptcy", due_from: Date.current.iso8601, due_to: Date.current.iso8601)
    expect(response.body).to include("共 32 项", "下一页")
    html = Nokogiri::HTML(response.body)
    expect(html.css("tbody tr").count).to eq(30)
    next_link = html.css("nav[aria-label='项目分页'] a").last["href"]
    expect(next_link).to include("type=bankruptcy", "due_from=", "due_to=")
    get next_link
    expect(response.body).to include("第 2 页", project.code)
    expect(Nokogiri::HTML(response.body).css("tbody tr").count).to eq(2)
    get projects_path(due_from: "2026-09-10", due_to: "2026-09-01")
    expect(response).to redirect_to(projects_path)
    follow_redirect!
    expect(response.body).to include("截止日期起不能晚于截止日期止")
    get projects_path(due_from: "invalid")
    expect(response).to redirect_to(projects_path)
    get projects_path(page: "9999999999999999999999999999999")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("第 2 页")
  end

  it "筛选选项不暴露不可见项目负责人和部门，并保留历史停用部门" do
    visible = Department.create!(code: "VISIBLE", name: "历史可见部门", active: false)
    hidden = Department.create!(code: "HIDDEN", name: "不可见部门", active: true)
    project.update!(department: visible)
    outsider = create_user(email: "hidden-owner@example.test", name: "不可见负责人")
    create_project(owner: outsider, code: "HIDDEN").update!(department: hidden)
    reader = create_user(email: "project-reader@example.test")
    ProjectMembership.create!(project: project, user: reader, membership_role: "observer")
    delete session_path
    sign_in(reader)
    get projects_path
    expect(response.body).to include("历史可见部门", "共 1 项")
    expect(response.body).not_to include("不可见部门", "不可见负责人", "HIDDEN")
  end
end

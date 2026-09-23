require "rails_helper"

RSpec.describe "部门汇总与个人看板", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:member) { create_user(email: "report-reader@example.test") }
  let!(:department) { Department.create!(name: "业务一部", code: "REPORT-A") }
  let!(:hidden_department) { Department.create!(name: "保密部门", code: "REPORT-HIDDEN") }
  let!(:visible) do
    p = create_project(owner: member, code: "REPORT-1", name: "可见项目一")
    p.update!(department: department, start_date: Date.current - 60, due_date: Date.current - 1)
    ProjectMembership.create!(project: p, user: admin, membership_role: "member")
    p
  end
  let!(:unassigned) { create_project(owner: member, code: "REPORT-2", name: "无部门项目") }
  let!(:hidden) do
    p = create_project(owner: admin, code: "REPORT-H", name: "不得显示的项目")
    p.update!(department: hidden_department)
    p
  end
  before { sign_in(member) }

  def fee(project, receivable, received)
    project.fees.create!(created_by: admin, fee_type: "agency", receivable: receivable, received: received, invoice_status: "not_issued")
  end

  it "多个成员与多笔收费不重复项目，未收与溢收不相互抵销" do
    fee(visible, 100, 60)
    fee(visible, 20, 30)
    fee(hidden, 999_999, 888_888)
    visible.claims.create!(created_by: member, creditor_name: "CNY", claim_amount: 100, currency: "CNY")
    visible.claims.create!(created_by: member, creditor_name: "USD", claim_amount: 100, currency: "USD")
    scope = ProjectPolicy::Scope.new(member, Project).resolve
    report = DepartmentReport.new(scope)
    expect(report.totals).to include(projects: 2, ongoing: 2, overdue: 1, claims: 2, pending_claims: 2, receivable: 120, received: 90, outstanding: 40, overpaid: 10)
    get department_reports_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("业务一部", "未分配部门", "不混加不同币种")
    expect(response.body).not_to include("不得显示的项目", "保密部门", "999,999")
    get department_reports_path(department_id: hidden_department.id)
    expect(response.body).to include("共 0 项")
    expect(response.body).not_to include("不得显示的项目")
  end

  it "日期、业务、阶段筛选作用于同一项目集合，完成归档不计超期" do
    unassigned.update!(status: "completed", project_type: "bid")
    visible.update!(status: "archived", archive_reason: "测试归档")
    report = DepartmentReport.new(ProjectPolicy::Scope.new(member, Project).resolve)
    expect(report.totals).to include(completed: 1, archived: 1, ongoing: 0, overdue: 0)
    get department_reports_path(from: Date.current.to_s, to: Date.current.to_s, type: "bid", status: "completed")
    expect(response.body).to include("无部门项目", "共 1 项")
    expect(response.body).not_to include("可见项目一")
    get department_reports_path(view: "completed_tenders")
    expect(response.body).to include("共 1 项", "无部门项目")
    expect(response.body).not_to include("可见项目一")
    get department_reports_path(department_id: "unassigned")
    expect(response.body).to include("共 1 项")
    get department_reports_path(from: "not-a-date")
    expect(response).to redirect_to(department_reports_path)
    get department_reports_path(from: (Date.current + 1).to_s, to: Date.current.to_s)
    expect(response).to redirect_to(department_reports_path)
  end

  it "CSV 遵循同一权限与筛选、审计导出并防公式注入" do
    department.update!(name: "=SUM(1,1)")
    fee(visible, 125.5, 100)
    get department_reports_path(format: :csv, department_id: department.id)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    data = CSV.parse(response.body.dup.force_encoding("UTF-8").delete_prefix("\uFEFF"))
    expect(data.size).to eq(2)
    expect(data[1][0]).to eq("'=SUM(1,1)")
    expect(data[1][8..11]).to eq([ "125.50", "100.00", "25.50", "0.00" ])
    expect(response.body).not_to include("保密部门")
    expect(AuditEvent.where(action: "department_report.export", actor: member)).to exist
    delete session_path
    get department_reports_path(format: :csv)
    expect(response).to redirect_to(new_session_path)
  end

  it "明细分页不截断汇总，撤销项目成员后页面与导出同时失效" do
    31.times { |i| create_project(owner: member, code: "REPORT-P#{i}") }
    get department_reports_path(page: 2)
    expect(response.body).to include("共 33 项", "上一页")
    expect(Nokogiri::HTML(response.body).css("table").last.css("tbody tr").size).to eq(3)
    visible.update!(owner: admin)
    visible.project_memberships.where(user: member).destroy_all
    get department_reports_path
    expect(response.body).not_to include("可见项目一")
    get department_reports_path(format: :csv, department_id: department.id)
    expect(CSV.parse(response.body.dup.force_encoding("UTF-8").delete_prefix("\uFEFF")).size).to eq(1)
  end

  it "个人待办统计含会签及未指定处理人的负责人任务，不暴露撤权任务" do
    direct = visible.workflow_tasks.create!(record: visible, assignee: member, stage: "本人办理")
    fallback = visible.workflow_tasks.create!(record: visible, stage: "负责人兜底")
    visible.workflow_tasks.create!(record: visible, assignee: admin, stage: "其他人办理")
    signed = visible.workflow_tasks.create!(record: visible, stage: "本人会签")
    signed.workflow_signatures.create!(user: member)
    signed.workflow_signatures.create!(user: admin)
    expect(WorkflowTask.pending_for(member, projects: ProjectPolicy::Scope.new(member, Project).resolve).pluck(:id)).to contain_exactly(direct.id, fallback.id, signed.id)
    get root_path
    expect(response.body).to include("本人办理", "本人会签")
    expect(response.body).not_to include("其他人办理")
    signed.workflow_signatures.find_by!(user: member).update!(status: "approved")
    expect(WorkflowTask.pending_for(member, projects: ProjectPolicy::Scope.new(member, Project).resolve).count).to eq(2)
    visible.update!(owner: admin)
    visible.project_memberships.where(user: member).destroy_all
    get root_path
    expect(response.body).not_to include("本人办理", "本人会签", "可见项目一")
  end
end

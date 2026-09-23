require "rails_helper"

RSpec.describe "项目交付控制", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  before { sign_in(admin) }

  it "完整台账展示旧记录并支持分页和搜索" do
    31.times { |index| project.claims.create!(created_by: admin, creditor_name: "债权人#{index}", claim_amount: 100) }
    get ledger_project_path(project, kind: "claims")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("下一页")
    table = Nokogiri::HTML(response.body).at_css("table.ledger-table")
    expect(table.css("th").map(&:text)).to eq([ "名称 / 编号", "业务分类", "金额", "状态", "创建时间", "操作" ])
    expect(table.css("tbody tr").size).to eq(30)
    get ledger_project_path(project, kind: "claims", page: 2)
    expect(response.body).to include("债权人0")
    get ledger_project_path(project, kind: "claims", q: "债权人0")
    expect(response.body).to include("共 1 条")
    get ledger_project_path(project, kind: "users")
    expect(response).to have_http_status(:not_found)
  end

  it "终审后拒绝再次提交，跨项目审核权限不能越界" do
    claim = project.claims.create!(created_by: admin, creditor_name: "终审测试", claim_amount: 100, status: "approved", review_stage: "principal")
    expect do
      post review_claim_path(claim), params: { stage: "principal", decision: "reject", comment: "重复提交" }
    end.not_to change(ClaimReview, :count)
    expect(claim.reload.status).to eq("approved")
    outsider = create_user(email: "reviewer@example.test", permissions: [ "claims.review" ])
    delete session_path
    sign_in(outsider)
    claim.update!(status: "received", review_stage: "initial")
    expect do
      post review_claim_path(claim), params: { stage: "initial", decision: "approve", comment: "越界" }
    end.not_to change(ClaimReview, :count)
  end

  it "归档必须说明原因，并记录操作人和时间" do
    patch project_path(project), params: { project: { status: "archived" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(project.reload.status).to eq("active")
    patch project_path(project), params: { project: { status: "archived", archive_reason: "成果交付，资料已核对" } }
    expect(project.reload.archived_by).to eq(admin)
    expect(project.archived_at).to be_present
    get project_path(project)
    expect(response.body).to include("成果交付，资料已核对")
  end

  it "自定义清单只影响新申报，并拒绝跨项目引用" do
    post project_claim_checklists_path(project), params: { claim_checklist: { name: "职工清单", claim_type: "employee", active: true, material_types_text: "劳动合同\n工资明细" } }
    checklist = project.claim_checklists.last!
    post project_claims_path(project), params: { claim_checklist_id: checklist.public_id, claim: { creditor_name: "张先生", claim_amount: 100, claimed_type: "employee" } }
    expect(project.claims.last!.claim_materials.pluck(:material_type)).to match_array([ "劳动合同", "工资明细" ])
    other = create_project(owner: admin, code: "OTHER")
    expect do
      post project_claims_path(other), params: { claim_checklist_id: checklist.public_id, claim: { creditor_name: "跨项目", claim_amount: 100, claimed_type: "employee" } }
    end.not_to change(Claim, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "项目节点只可分派给项目成员，完成时间由服务端记录" do
    outsider = create_user(email: "outside@example.test")
    post project_project_milestones_path(project), params: { project_milestone: { title: "交付", stage: "结项", owner_id: outsider.id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(project.project_milestones).to be_empty
    post project_project_milestones_path(project), params: { project_milestone: { title: "交付", stage: "结项", owner_id: admin.id, status: "completed" } }
    expect(project.project_milestones.last!.completed_on).to eq(Date.current)
    get project_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("维护节点")
  end
end

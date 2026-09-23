require "rails_helper"

RSpec.describe "完整投标台账和只读资产详情", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  before { sign_in(admin) }

  it "资产来源可登记、检索、关联只读查看并进入每次版本快照" do
    post project_assets_path(project), params: { asset: { asset_code: "SOURCE-001", name: "合成重型设备", category: "设备", disposal_status: "pending", source_reference: "CONTRACT-7788", description: "第七页合成附件凭证", change_reason: "合成来源登记" } }
    expect(response).to have_http_status(:redirect)
    asset = project.assets.find_by!(asset_code: "SOURCE-001")
    expect(asset.asset_versions.last.snapshot).to include("source_reference" => "CONTRACT-7788", "description" => "第七页合成附件凭证")
    related = project.assets.create!(updated_by: admin, asset_code: "SOURCE-002", name: "合成重型设备二", category: "设备", disposal_status: "pending", source_reference: "CONTRACT-7788")
    %w[CONTRACT-7788 第七页合成附件凭证 SOURCE-001].each do |query|
      get ledger_project_path(project, kind: "assets", q: query)
      expect(response.body).to include(project_asset_path(project, asset))
    end
    get ledger_project_path(project, kind: "assets", q: "%_")
    expect(response.body).to include("共 0 条")
    get project_asset_path(project, asset)
    expect(response.body).to include(project_asset_path(project, related), "名称文字相似", "来源与资产特征")
    patch project_asset_path(project, asset), params: { asset: { source_reference: "CONTRACT-NEW", description: "第八页修正", change_reason: "修正来源" } }
    expect(asset.asset_versions.order(:id).pluck(:snapshot).map { |snapshot| snapshot["source_reference"] }).to eq([ "CONTRACT-7788", "CONTRACT-NEW" ])
  end

  it "缺失或非法修改原因友好拒绝并回滚资产和版本，超长说明同样拒绝" do
    asset = project.assets.create!(updated_by: admin, asset_code: "REASON", name: "合成设备", category: "设备", disposal_status: "pending")
    [ nil, " ", { bad: "shape" }, [ "bad" ] ].each do |reason|
      patch project_asset_path(project, asset), params: { asset: { name: "不得保存", change_reason: reason } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("不能为空")
      expect(asset.reload.name).to eq("合成设备")
      expect(asset.asset_versions.count).to eq(0)
    end
    patch project_asset_path(project, asset), params: { asset: { description: "字" * 2001, change_reason: "太长" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(asset.reload.description).to be_nil
  end

  it "投标分析全部分页、按评分点或编号检索且保留失败记录" do
    records = 31.times.map { |i| project.bid_analyses.create!(criteria: [ "合成评分点#{i}" ], status: i.zero? ? "failed" : "draft") }
    get ledger_project_path(project, kind: "bids")
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("table tbody tr").size).to eq(30)
    expect(response.body).to include("共 31 条", "下一页")
    get ledger_project_path(project, kind: "bids", page: 2)
    expect(response.body).to include(records.first.public_id, bid_analysis_path(records.first))
    get ledger_project_path(project, kind: "bids", q: "合成评分点0")
    expect(response.body).to include("共 1 条", records.first.public_id)
    get ledger_project_path(project, kind: "bids", q: records.last.public_id)
    expect(response.body).to include("共 1 条")
    get ledger_project_path(project, kind: "bids", q: "%_")
    expect(response.body).to include("共 0 条")
  end

  it "观察者可以查看资产版本但不能编辑，撤销项目成员后不可继续读取" do
    asset = project.assets.create!(updated_by: admin, asset_code: "SYNTHETIC-001", name: "合成设备", category: "设备", appraisal_value: 100, disposal_status: "pending")
    asset.capture_version!(actor: admin, change_reason: "合成初始登记")
    patch project_asset_path(project, asset), params: { asset: { appraisal_value: 150, rights_no: "合成权属号", change_reason: "合成价值调整" } }
    observer = create_user(email: "asset-observer@example.test")
    membership = project.project_memberships.create!(user: observer, membership_role: "observer")
    delete session_path
    sign_in(observer)
    get ledger_project_path(project, kind: "assets")
    expect(response.body).to include(project_asset_path(project, asset))
    get project_asset_path(project, asset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("合成初始登记", "合成价值调整", "合成权属号", "共 2 个版本")
    expect(response.body).not_to include("维护资产")
    expect do
      patch project_asset_path(project, asset), params: { asset: { appraisal_value: 999, change_reason: "越权" } }
    end.not_to change(AssetVersion, :count)
    expect(asset.reload.appraisal_value).to eq(150)
    other = create_project(owner: admin, code: "ASSET-OTHER")
    get project_asset_path(other, asset)
    expect(response).to have_http_status(:not_found)
    membership.destroy!
    get project_asset_path(project, asset)
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("合成权属号")
  end

  it "通用项目管理权限不能越过项目成员边界编辑或读取台账" do
    manager = create_user(email: "outside-manager@example.test", permissions: [ "projects.manage" ])
    delete session_path
    sign_in(manager)
    get ledger_project_path(project, kind: "bids")
    expect(response).to have_http_status(:redirect)
    patch project_path(project), params: { project: { name: "越权修改" } }
    expect(project.reload.name).not_to eq("越权修改")
    expect do
      post project_assets_path(project), params: { asset: { asset_code: "FOREIGN", name: "越权", category: "设备", disposal_status: "pending", change_reason: "越权" } }
    end.not_to change(Asset, :count)
  end

  it "资产版本创建失败时回滚价值修改" do
    asset = project.assets.create!(updated_by: admin, asset_code: "ROLLBACK", name: "合成回滚设备", category: "设备", appraisal_value: 100, disposal_status: "pending")
    allow_any_instance_of(Asset).to receive(:capture_version!).and_raise(ActiveRecord::RecordInvalid.new(AssetVersion.new))
    patch project_asset_path(project, asset), params: { asset: { appraisal_value: 200, change_reason: "模拟失败" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(asset.reload.appraisal_value).to eq(100)
    expect(asset.asset_versions).to be_empty
  end

  it "项目未收费用不被其他收费的溢收抵销" do
    project.fees.create!(created_by: admin, fee_type: "agency", receivable: 500, received: 100)
    project.fees.create!(created_by: admin, fee_type: "expert", receivable: 100, received: 150)
    get project_path(project)
    html = Nokogiri::HTML(response.body)
    label = html.css("p").find { |p| p.text == "未收费用" }
    expect(label.parent.text).to include("400.00")
    expect(label.parent.text).not_to include("350.00")
  end
end

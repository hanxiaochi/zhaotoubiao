require "rails_helper"

RSpec.describe AssetRiskAnalyzer do
  include AuthenticationHelpers

  let!(:user) { create_user(email: "similarity@example.test") }
  let!(:project) { create_project(owner: user, code: "SIMILARITY") }

  def asset_in(project, code, **attributes)
    project.assets.create!({ updated_by: user, asset_code: code, name: "合成机器设备", category: "设备", disposal_status: "pending" }.merge(attributes))
  end

  def similarities(asset)
    described_class.call(asset).select { |flag| flag["code"] == "similar_asset" }
  end

  it "按同类名称和来源说明提示并保留不同设备编号，不修改记录" do
    asset = asset_in(project, "A", description: "合成合同第九页设备清单编号1001")
    related = asset_in(project, "B", name: "合成机器设备一", description: "合成合同第九页设备清单编号1002")
    before = project.assets.order(:id).map(&:attributes)
    flags = similarities(asset)
    expect(flags.first["related_public_ids"]).to eq([ related.public_id ])
    expect(flags.first["message"]).to include("名称文字相似", "来源说明文字相似", "须逐项核对")
    expect(project.assets.order(:id).map(&:attributes)).to eq(before)
  end

  it "归一化全角来源编号，跨类别提示同来源但不扫描其他项目" do
    asset = asset_in(project, "A", source_reference: " ＡＢ－１２３ ")
    related = asset_in(project, "B", source_reference: "ab-123", category: "房产")
    other = create_project(owner: user, code: "OTHER-SIMILARITY")
    foreign = asset_in(other, "C", source_reference: "AB123")
    flags = similarities(asset)
    expect(flags.pluck("related_public_ids").flatten).to eq([ related.public_id ])
    expect(flags.to_s).not_to include(foreign.public_id)
    expect(flags.first["message"]).to include("相同合同/来源编号")
    expect(flags.first["message"]).not_to include("名称文字相似")
  end

  it "短名称与不同类别不被相似文本误触发，重复字串按次数计算" do
    short = asset_in(project, "A", name: "设备一")
    asset_in(project, "B", name: "设备一")
    expect(similarities(short)).to be_empty
    repetitive = asset_in(project, "C", name: "aaaa")
    asset_in(project, "D", name: "aaaaaaaaaaaaaaaa")
    asset_in(project, "E", name: "aaaa", category: "房产")
    expect(similarities(repetitive)).to be_empty
  end

  it "扫描超过展示上限的同项目记录并明确报告未展开数量" do
    asset = asset_in(project, "A")
    23.times { |index| asset_in(project, "M-#{index}") }
    flags = described_class.call(asset)
    expect(flags.count { |flag| flag["code"] == "similar_asset" }).to eq(20)
    expect(flags.last["message"]).to include("另有3条")
  end

  it "提示相同权证和地址，同时保留非结论性数据缺口" do
    user = create_user(email: "asset-risk@example.com")
    project = create_project(owner: user, code: "ASSET-RISK")
    Asset.create!(project: project, updated_by: user, asset_code: "A-1", name: "厂房一", category: "房产", rights_no: " 苏A-001 ", address: "南京市 鼓楼区1号", appraisal_org: "评估公司", appraisal_value: 100, disposal_status: "pending")
    asset = Asset.create!(project: project, updated_by: user, asset_code: "A-2", name: "厂房二", category: "房产", rights_no: "苏a-001", address: "南京市鼓楼区1号", disposal_status: "pending")

    codes = described_class.call(asset).pluck("code")

    expect(codes).to include("duplicate_rights_no", "duplicate_address", "missing_appraisal")
  end
end

# Synthetic fixtures only. Run after the owner creates the first administrator.
abort "Requires DEMO_DATA_ONLY=true" unless ENV["DEMO_DATA_ONLY"] == "true"
admin = User.active.joins(:roles).find_by!(roles: { code: "admin" })
Project.transaction do
  [ [ "bankruptcy", "合成演示：东华示例企业破产管理" ],
    [ "tender_agency", "合成演示：办公设备采购招标代理" ],
    [ "bid", "合成演示：审计服务投标辅助" ] ].each do |kind, name|
    code = "OWNER-DEMO-#{kind.upcase}"
    project = Project.find_by(code: code)
    if project && project.metadata["owner_demo_fixture"] != "v1"
      abort "Reserved demo code collision; existing records preserved"
    end
    project ||= Project.create!(code: code, name: name, project_type: kind, status: "active", owner: admin,
      start_date: Date.current, due_date: Date.current + 30, metadata: { "owner_demo_fixture" => "v1", "client_name" => "虚构企业（非真实客户）" })
    project.fees.find_or_create_by!(fee_type: "agency") do |fee|
      fee.assign_attributes(created_by: admin, receivable: 20000, received: 5000,
        invoice_status: "not_issued", note: "合成演示数据，不可用于真实收费")
    end
    next unless kind == "bankruptcy"

    project.assets.find_or_create_by!(asset_code: "DEMO-ASSET-001") do |asset|
      asset.assign_attributes(name: "合成设备：办公电脑", category: "设备", disposal_status: "待处置",
        appraisal_value: 12000, updated_by: admin, source_reference: "合成演示清单（不构成估值意见）")
    end
    project.claims.find_or_create_by!(creditor_name: "合成债权人甲（非真实主体）") do |claim|
      claim.assign_attributes(created_by: admin, claim_amount: 100000, currency: "CNY", claimed_type: "ordinary",
        status: "received", review_stage: "initial", analysis_data: {})
    end
  end
end
puts "Synthetic projects, fees, asset and unapproved claim ready. No AI result or approval fabricated."

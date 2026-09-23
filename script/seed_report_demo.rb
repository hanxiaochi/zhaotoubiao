# Run only against the local development database; no production or customer imports.
abort "Only available in development" unless Rails.env.development?
admin = User.find_by!(email: "qa.admin@example.test")
department = Department.find_or_create_by!(code: "QA-REPORT-DEMO") { |d| d.name = "合成验收部门" }
[ [ "QA-REPORT-CLOSED", "completed", "tender_agency", 1000, 600 ],
  [ "QA-REPORT-ARCHIVED", "archived", "bid", 200, 250 ] ].each do |code, status, kind, due, paid|
  project = Project.find_or_create_by!(code: code) do |item|
    item.assign_attributes(name: "合成汇总验收 #{code}", project_type: kind, status: status, owner: admin,
      department: department, start_date: Date.current - 30, due_date: Date.current - 1)
    if status == "archived"
      item.assign_attributes(archive_reason: "合成汇总验证，非客户业务", archived_by: admin, archived_at: Time.current)
    end
  end
  project.fees.find_or_create_by!(fee_type: "agency") do |fee|
    fee.assign_attributes(created_by: admin, receivable: due, received: paid, invoice_status: "not_issued", note: "合成收费，仅验收汇总")
  end
end
puts "Synthetic report fixtures ready."

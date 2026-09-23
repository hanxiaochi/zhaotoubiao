abort "Development-only synthetic acceptance data" unless Rails.env.development?
password = ENV.fetch("QA_SIGNER_PASSWORD")
admin = User.find_by!(email: "qa.admin@example.test")
signer = User.find_or_initialize_by(email: "qa.claim.signer@example.test")
unless signer.persisted?
  signer.assign_attributes(name: "合成独立会签人", status: "active", password: password, password_confirmation: password)
  signer.save!
end
project = Project.find_or_create_by!(code: "QA-CLAIM-GATE-0907") do |item|
  item.assign_attributes(name: "合成债权闭环验收（非客户业务）", owner: admin, project_type: "bankruptcy", status: "active", start_date: Date.current)
end
project.project_memberships.find_or_create_by!(user: admin) { |item| item.membership_role = "owner" }
project.project_memberships.find_or_create_by!(user: signer) { |item| item.membership_role = "member" }
claim = project.claims.find_or_create_by!(creditor_name: "合成设备款债权") do |item|
  item.assign_attributes(created_by: admin, claim_amount: 12345, summary: "仅用于页面与状态机验收，非实际法律事实。")
end
unless claim.claim_materials.exists?
  document = project.project_documents.create!(uploaded_by: admin, category: "claim", status: "uploaded",
    original_filename: "合成申报原件.txt", content_type: "text/plain", ocr_status: "not_required",
    file: { io: StringIO.new("合成设备款申报：12345元。此文件仅用于功能验收，不代表真实债权、签字或盖章。"), filename: "合成申报原件.txt", content_type: "text/plain" })
  claim.claim_materials.create!(material_type: "合成申报书", present: true, project_document: document)
end
puts "CLAIM_PATH=/claims/#{claim.public_id}"
puts "PROJECT_PATH=/projects/#{project.public_id}"

# Synthetic legacy-schema upgrade and backup-restore verification only.
require "digest"
require "json"
require "fileutils"
abort "Test environment required" unless Rails.env.test?
config = ApplicationRecord.connection_db_config
abort "Only dedicated loopback upgrade/rollback databases are allowed" unless config.adapter == "postgresql" && config.host == "127.0.0.1" && config.database.match?(/\Adonghua_(?:\d+_)?(?:upgrade|rollback)_test\z/)
abort "Run from an isolated clean-install candidate" unless Rails.root.to_s.tr("\\", "/").match?(%r{/tmp/clean-install-[^/]+/source\z})
storage_root = Pathname.new(ActiveStorage::Blob.service.root).expand_path
abort "Attachment storage must stay under this isolated candidate tmp" unless storage_root.to_s.start_with?(Rails.root.join("tmp").to_s + File::SEPARATOR) && !storage_root.symlink?

connection = ApplicationRecord.connection
directory = Rails.root.join("tmp/upgrade-evidence")
manifest_path = directory.join("legacy-manifest.json")
legacy_version = "20260903023000"
mode = ARGV.fetch(0)

def legacy_record(table, **attributes)
  klass = Class.new(ApplicationRecord) { self.table_name = table }
  values = attributes.stringify_keys
  values["public_id"] = SecureRandom.uuid if klass.column_names.include?("public_id")
  klass.create!(values)
end

def table_snapshot(connection, table, columns)
  names = columns.map { |name| connection.quote_column_name(name) }.join(",")
  rows = connection.select_all("SELECT #{names} FROM #{connection.quote_table_name(table)}").to_a.map { |row| row.sort.to_h.to_json }.sort
  { columns: columns, count: rows.size, sha256: Digest::SHA256.hexdigest(rows.join("\n")) }
end

case mode
when "seed-legacy"
  abort "Seed only a fresh legacy-schema upgrade database" unless config.database.end_with?("_upgrade_test") && connection.select_value("SELECT MAX(version) FROM schema_migrations") == legacy_version && User.count.zero? && !manifest_path.exist?
  ApplicationRecord.transaction do
    user = legacy_record("users", name: "Synthetic upgrade administrator", email: "upgrade@example.test", password_digest: BCrypt::Password.create(SecureRandom.hex(32)).to_s)
    role = legacy_record("roles", code: "admin", name: "Synthetic admin", permissions: [ "*" ])
    legacy_record("user_roles", user_id: user.id, role_id: role.id)
    department = legacy_record("departments", code: "UPGRADE", name: "Synthetic upgrade department")
    project = legacy_record("projects", owner_id: user.id, department_id: department.id, code: "UPGRADE-LEGACY", name: "Synthetic legacy project", project_type: "bankruptcy", status: "active", metadata: { "client_name" => "Synthetic client" })
    legacy_record("project_memberships", project_id: project.id, user_id: user.id, membership_role: "owner")
    legacy_record("intake_items", project_id: project.id, created_by_id: user.id, name: "Synthetic legacy intake", category: "financial", status: "received")
    asset = legacy_record("assets", project_id: project.id, updated_by_id: user.id, asset_code: "LEGACY-A1", name: "Synthetic legacy equipment", category: "equipment", appraisal_value: "123.45")
    legacy_record("asset_versions", asset_id: asset.id, changed_by_id: user.id, change_reason: "Synthetic legacy registration", appraisal_value: "123.45", snapshot: { "appraisal_value" => "123.45" })
    bytes = "Synthetic legacy original; no customer data.\n"
    document = ProjectDocument.create!(project_id: project.id, uploaded_by_id: user.id, category: "claim", original_filename: "synthetic-legacy.txt", status: "uploaded", ocr_status: "not_required", content_type: "text/plain", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), file: { io: StringIO.new(bytes), filename: "synthetic-legacy.txt", content_type: "text/plain" })
    claim = legacy_record("claims", project_id: project.id, created_by_id: user.id, creditor_name: "Synthetic legacy creditor", claim_amount: "12345.67", status: "pending_approval", review_stage: "professional")
    legacy_record("claim_materials", claim_id: claim.id, project_document_id: document.id, material_type: "Synthetic legacy evidence", present: true, checked_by_id: user.id, signature_detected: true, seal_detected: true)
    legacy_record("claim_reviews", claim_id: claim.id, reviewer_id: user.id, stage: "initial", decision: "approve", comment: "Synthetic historical approval without modern snapshot")
    legacy_record("fees", project_id: project.id, created_by_id: user.id, fee_type: "agency", receivable: "1000.00", received: "200.50", invoice_status: "issued")
    legacy_record("bid_analyses", project_id: project.id, status: "draft", criteria: [ "Synthetic criterion" ], risks: [], outline: [ "Synthetic section" ])
    legacy_record("generated_documents", project_id: project.id, created_by_id: user.id, kind: "bid_technical", title: "Synthetic legacy draft", content: "Retain the exact old document body", status: "draft")
    legacy_record("audit_events", actor_id: user.id, action: "synthetic.legacy", record_type: "Project", record_id: project.id, record_public_id: project.public_id, occurred_at: Time.current)
  end
  FileUtils.mkdir_p(directory.join("originals"))
  tables = (connection.tables - %w[ar_internal_metadata schema_migrations]).sort.to_h do |table|
    [ table, table_snapshot(connection, table, connection.columns(table).map(&:name).sort) ]
  end
  originals = ActiveStorage::Blob.order(:id).map do |blob|
    bytes = blob.download
    File.binwrite(directory.join("originals", blob.key), bytes)
    { key: blob.key, bytes: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
  end
  manifest_path.write(JSON.pretty_generate(version: legacy_version, tables: tables, originals: originals))
  puts({ mode: mode, tables: tables.size, records: tables.values.sum { |item| item[:count] }, originals: originals.size }.to_json)
when "verify-upgrade", "verify-rollback"
  manifest = JSON.parse(manifest_path.read)
  manifest.fetch("tables").each do |table, expected|
    actual = table_snapshot(connection, table, expected.fetch("columns"))
    raise "Legacy rows changed in #{table}" unless JSON.parse(actual.to_json) == expected
  end
  if mode == "verify-upgrade"
    raise "Upgrade migrations missing" unless connection.table_exists?(:claim_supplements) && connection.column_exists?(:generated_documents, :bid_basis_snapshot)
    raise "Latest source/section migration missing" unless connection.column_exists?(:assets, :source_reference) && connection.column_exists?(:assets, :description) && connection.column_exists?(:bid_analyses, :suggested_tasks)
    raise "Legacy source or clauses were invented" unless Asset.sole.source_reference.nil? && Asset.sole.description.nil? && BidAnalysis.sole.qualification_requirements == [] && BidAnalysis.sole.suggested_tasks == []
    material = ClaimMaterial.sole
    raise "Legacy evidence was silently deemed verified" unless material.signature_requirement == "undetermined" && material.review_issues.any?
    raise "Legacy approval snapshot was invented" unless ClaimReview.sole.evidence_snapshot == {} && ClaimReview.sole.basis_sha256.nil?
    raise "Legacy draft basis was invented" unless GeneratedDocument.sole.bid_basis_snapshot == {} && GeneratedDocument.sole.bid_analysis_id.nil?
  else
    raise "Wrong rollback target" unless config.database.end_with?("_rollback_test")
    raise "Rollback schema differs" unless connection.select_value("SELECT MAX(version) FROM schema_migrations") == manifest.fetch("version") && !connection.table_exists?(:claim_supplements)
    manifest.fetch("originals").each do |item|
      path = directory.join("originals", item.fetch("key"))
      raise "Original backup digest mismatch" unless Digest::SHA256.file(path).hexdigest == item.fetch("sha256")
      blob = ActiveStorage::Blob.find_by!(key: item.fetch("key"))
      File.open(path, "rb") { |io| blob.service.upload(blob.key, io, checksum: blob.checksum) }
    end
  end
  manifest.fetch("originals").each do |item|
    bytes = ActiveStorage::Blob.find_by!(key: item.fetch("key")).download
    raise "Original differs" unless bytes.bytesize == item.fetch("bytes") && Digest::SHA256.hexdigest(bytes) == item.fetch("sha256")
  end
  puts({ mode: mode, tables_verified: manifest.fetch("tables").size, records_verified: manifest.fetch("tables").values.sum { |item| item.fetch("count") }, originals_verified: manifest.fetch("originals").size }.to_json)
when "exercise-upgraded"
  abort "Only the upgraded synthetic database may be changed" unless config.database.end_with?("_upgrade_test") && manifest_path.exist?
  project = Project.find_by!(code: "UPGRADE-LEGACY")
  user = project.owner
  Current.user = user
  ApplicationRecord.transaction do
    milestone = project.project_milestones.create!(title: "Synthetic post-upgrade milestone", stage: "review", due_on: Date.current + 7, owner: user)
    document = project.generated_documents.create!(created_by: user, kind: "general", title: "Synthetic post-upgrade draft", content: "New body after upgrade", status: "draft")
    asset = project.assets.create!(updated_by: user, asset_code: "POST-UPGRADE", name: "Synthetic new equipment", category: "equipment", disposal_status: "pending", source_reference: "SYNTHETIC-CONTRACT", description: "Synthetic new source")
    asset.capture_version!(change_reason: "Synthetic post-upgrade source", actor: user)
    analysis = project.bid_analyses.create!(qualification_requirements: [ "Synthetic qualification" ], suggested_tasks: [ "Synthetic suggested task" ])
    raise "New asset snapshot missing" unless asset.asset_versions.sole.snapshot["source_reference"] == "SYNTHETIC-CONTRACT"
    raise "New bid section missing" unless analysis.reload.suggested_tasks == [ "Synthetic suggested task" ]
    Audit::Recorder.call(action: "synthetic.upgraded_write", record: document)
    raise "Post-upgrade records not persisted" unless milestone.reload.title.present? && document.reload.bid_basis_snapshot == {}
  end
  raise "Post-upgrade audit missing" unless AuditEvent.where(action: "synthetic.upgraded_write").count == 1
  puts({ mode: mode, milestones: project.project_milestones.count, documents: project.generated_documents.count, audits: AuditEvent.where(action: "synthetic.upgraded_write").count }.to_json)
else
  abort "Use seed-legacy, verify-upgrade, exercise-upgraded or verify-rollback"
end

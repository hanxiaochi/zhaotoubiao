# Compare every synthetic table and every original attachment before/after pg_restore.
abort "Test environment required" unless Rails.env.test?
config = ApplicationRecord.connection_db_config
abort "Use dedicated loopback test databases" unless config.adapter == "postgresql" && config.host == "127.0.0.1" && config.database.in?(%w[donghua_concurrency_test donghua_restore_test])
mode = ARGV.fetch(0)
directory = Rails.root.join("tmp/postgres-runtime/restore-evidence")
manifest_path = directory.join("manifest.json")
require "fileutils"

if mode == "backup"
  abort "Backup already exists; retain the original evidence" if manifest_path.exist?
  FileUtils.mkdir_p(directory.join("originals"))
elsif mode == "restore-files"
  abort "Restore only into the dedicated restore database" unless config.database == "donghua_restore_test"
  manifest = JSON.parse(manifest_path.read)
  manifest.fetch("files").each do |item|
    blob = ActiveStorage::Blob.find(item.fetch("id"))
    path = directory.join("originals", blob.key)
    raise "Backup file digest mismatch" unless Digest::SHA256.file(path).hexdigest == item.fetch("sha256")
    File.open(path, "rb") { |io| blob.service.upload(blob.key, io, checksum: blob.checksum) }
  end
elsif mode != "verify"
  abort "Use backup, restore-files or verify"
end

connection = ApplicationRecord.connection
tables = (connection.tables - %w[ar_internal_metadata schema_migrations]).sort.to_h do |table|
  records = connection.select_all("SELECT * FROM #{connection.quote_table_name(table)}").to_a.map { |row| row.sort.to_h.to_json }.sort
  [ table, { count: records.size, sha256: Digest::SHA256.hexdigest(records.join("\n")) } ]
end
files = ActiveStorage::Blob.order(:id).map do |blob|
  bytes = blob.download
  digest = Digest::SHA256.hexdigest(bytes)
  raise "Stored original checksum mismatch" unless Base64.strict_encode64(Digest::MD5.digest(bytes)) == blob.checksum
  ProjectDocument.joins(file_attachment: :blob).where(active_storage_blobs: { id: blob.id }).each do |document|
    raise "Document SHA-256 mismatch" unless document.sha256 == digest
  end
  File.binwrite(directory.join("originals", blob.key), bytes) if mode == "backup"
  { id: blob.id, key: blob.key, bytes: bytes.bytesize, sha256: digest }
end
snapshot = { tables: tables, files: files }
if mode == "backup"
  manifest_path.write(JSON.pretty_generate(snapshot))
else
  raise "Restored table or attachment manifest differs" unless JSON.parse(manifest_path.read) == JSON.parse(snapshot.to_json)
end
puts({ mode: mode, tables_verified: tables.size, records_verified: tables.values.sum { |item| item[:count] }, originals_verified: files.size, original_bytes: files.sum { |item| item[:bytes] } }.to_json)

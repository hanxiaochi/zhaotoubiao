# Export the current worktree candidate without local data/secrets or Git history.
# This does not commit, publish, or claim that the candidate is a final release.
require "open3"
require "fileutils"
require "digest"
require "json"
require "pathname"

root = Pathname.new(__dir__).parent.expand_path
destination = root.join("tmp", ARGV.fetch(0, "clean-install-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}")).expand_path
abort "Destination must be a new direct child of project tmp" unless destination.parent == root.join("tmp") && !destination.exist?
listing, error, result = Open3.capture3("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", chdir: root.to_s)
abort "Cannot enumerate worktree candidate: #{error}" unless result.success?
paths = listing.split("\0").uniq.sort
manifest = []
paths.each do |relative|
  source = root.join(relative).expand_path
  abort "Unsafe candidate path" unless source.to_s.start_with?(root.to_s + File::SEPARATOR) && source.file? && !source.symlink?
  forbidden = relative.match?(%r{(?:\A|/)(?:\.git|\.bundle|\.venv|__pycache__)/|\.(?:key|sqlite3?|log|dump)\z|(?:\A|/)\.env(?:\.|\z)}) && relative != ".env.example"
  abort "Local-only file would enter candidate: #{relative}" if forbidden
  abort "Unexpected large source file: #{relative}" if source.size > 10 * 1024 * 1024
  bytes = source.binread
  abort "Credential-shaped content found in candidate: #{relative}" if bytes.match?(/sk-cp-[A-Za-z0-9_-]{30,}/n)
  %w[RELEASE_SECRET_1 RELEASE_SECRET_2].each do |key|
    secret = ENV[key]
    abort "Forbidden secret found in candidate: #{relative}" if secret && secret.bytesize >= 16 && bytes.include?(secret.b)
  end
  target = destination.join("source", relative)
  FileUtils.mkdir_p(target.parent)
  File.binwrite(target, bytes)
  manifest << { path: relative, bytes: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
end
destination.join("source-manifest.json").write(JSON.pretty_generate(files: manifest, source_root: root.to_s, created_at_utc: Time.now.utc.to_s))
puts({ destination: destination.to_s, files: manifest.size, bytes: manifest.sum { |item| item[:bytes] }, manifest_sha256: Digest::SHA256.file(destination.join("source-manifest.json")).hexdigest }.to_json)

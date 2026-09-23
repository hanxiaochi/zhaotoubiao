require "open3"
require "pathname"

# Read-only candidate and reachable-history scan. Reports locations and rule names,
# never credential values or matching lines. Not a proof that data is non-sensitive.
class ReleaseScan
  PATTERNS = {
    "ai_credential" => /sk-(?:cp-|proj-|ant-)?[A-Za-z0-9_-]{30,}/n,
    "github_credential" => /gh[pousr]_[A-Za-z0-9]{30,}/n,
    "aws_access_key" => /(?:AKIA|ASIA)[A-Z0-9]{16}/n,
    "private_key" => /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/n,
    "literal_credential" => /(?:token|api[_-]?key|secret|password)["']?\s*[:=]\s*["'][A-Za-z0-9_-]{28,}["']/in
  }.freeze
  MAX_BYTES = 10 * 1024 * 1024

  def initialize(root:, secrets: [])
    @root = Pathname.new(root).expand_path
    @secrets = secrets.compact.reject(&:empty?).map(&:b)
    raise ArgumentError, "Exact credentials must each have at least 16 bytes" if @secrets.any? { |secret| secret.bytesize < 16 }
  end

  def content_rules(bytes)
    rules = PATTERNS.filter_map { |rule, pattern| rule if bytes.b.match?(pattern) }
    rules << "exact_credential" if @secrets.any? { |secret| bytes.b.include?(secret) }
    rules
  end

  def forbidden_path?(relative)
    return false if relative == ".env.example" || relative.end_with?("/.keep")

    relative.match?(%r{(?:\A|/)(?:\.env(?:\.|\z)|\.venv/|\.bundle/|__pycache__/)|\.(?:key|sqlite3?|log|dump|bak)\z|\A(?:storage|tmp|log)/})
  end

  def run
    issues = []
    paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split("\0").uniq
    paths.each do |relative|
      path = @root.join(relative).expand_path
      unless path.to_s.start_with?(@root.to_s + File::SEPARATOR) && path.file? && !path.symlink?
        issues << { location: "worktree:#{relative}", rule: "unsafe_or_missing_path" }
        next
      end
      issues << { location: "worktree:#{relative}", rule: "local_runtime_file" } if forbidden_path?(relative)
      if path.size > MAX_BYTES
        issues << { location: "worktree:#{relative}", rule: "oversized_file" }
        next
      end
      content_rules(path.binread).each { |rule| issues << { location: "worktree:#{relative}", rule: rule } }
    end

    revisions = git("rev-list", "--all").lines.map(&:strip)
    blobs = {}
    revisions.each do |revision|
      git("ls-tree", "-r", "-z", revision).split("\0").each do |entry|
        metadata, relative = entry.split("\t", 2)
        mode, type, oid = metadata.split(" ")
        next unless type == "blob"
        issues << { location: "history:#{revision}:#{relative}", rule: "symlink" } if mode == "120000"
        issues << { location: "history:#{revision}:#{relative}", rule: "local_runtime_file" } if forbidden_path?(relative)
        blobs[oid] ||= "history:#{revision}:#{relative}"
      end
      content_rules(git("cat-file", "commit", revision)).each { |rule| issues << { location: "commit:#{revision}", rule: rule } }
    end
    blobs.each do |oid, location|
      if git("cat-file", "-s", oid).to_i > MAX_BYTES
        issues << { location: location, rule: "oversized_file" }
        next
      end
      content_rules(git("cat-file", "blob", oid)).each { |rule| issues << { location: location, rule: rule } }
    end
    { files: paths.size, revisions: revisions.size, unique_history_blobs: blobs.size, exact_credentials: @secrets.size, issues: issues.uniq }
  end

  private

  def git(*arguments)
    output, _error, status = Open3.capture3("git", *arguments, chdir: @root.to_s, binmode: true)
    raise "Git scan failed (output withheld to avoid credential disclosure)" unless status.success?
    output
  end
end

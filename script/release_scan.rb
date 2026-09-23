require "json"
require_relative "../lib/release_scan"

secrets = %w[RELEASE_SECRET_1 RELEASE_SECRET_2].filter_map { |key| ENV[key].to_s unless ENV[key].to_s.empty? }
abort "Final scan requires both runtime-injected release credentials" if ARGV.include?("--require-exact") && secrets.size != 2
result = ReleaseScan.new(root: File.expand_path("..", __dir__), secrets: secrets).run
puts JSON.pretty_generate(result)
exit(result[:issues].empty? ? 0 : 1)

require "rails_helper"
require_relative "../../lib/release_scan"

RSpec.describe ReleaseScan do
  subject(:scanner) { described_class.new(root: Rails.root, secrets: [ "synthetic-" + "a" * 32 ]) }

  it "detects shaped and exact credentials without returning values" do
    values = { "ai_credential" => "sk-cp-" + "x" * 35, "github_credential" => "ghp_" + "x" * 35,
      "aws_access_key" => "AKIA" + "X" * 16, "exact_credential" => "synthetic-" + "a" * 32,
      "literal_credential" => "token = '" + "f" * 32 + "'", "private_key" => "-----BEGIN " + "RSA PRIVATE KEY-----" }
    values.each do |rule, value|
      expect(scanner.content_rules(value)).to include(rule)
      expect(scanner.content_rules(value).join).not_to include(value)
    end
  end

  it "allows templates, expressions and ordinary binary assets" do
    expect(scanner.content_rules("AI_API_KEY=\npassword = SecureRandom.hex(32)\n\xff\x00".b)).to eq([])
  end

  it "rejects runtime data and keys but preserves example and keep files" do
    %w[.env .env.local config/master.key storage/test.sqlite3 tmp/archive.txt services/ocr_worker/.venv/package.py].each do |path|
      expect(scanner.forbidden_path?(path)).to be(true)
    end
    %w[.env.example storage/.keep app/models/user.rb docs/screenshots/claim.png].each do |path|
      expect(scanner.forbidden_path?(path)).to be(false)
    end
  end
end

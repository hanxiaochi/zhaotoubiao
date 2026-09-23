# Actual HTTP acceptance against a new, isolated development installation only.
require "bundler/setup"
require "net/http"
require "nokogiri"
require "securerandom"
require "json"
require "tempfile"

abort "Run only from a clean-install candidate directory" unless Dir.pwd.tr("\\", "/").match?(%r{/tmp/clean-install-[^/]+/source\z})
abort "Explicit synthetic bootstrap confirmation required" unless ENV["SYNTHETIC_INSTALL_SMOKE"] == "1"
port = Integer(ENV.fetch("INSTALL_SMOKE_PORT", "3111"))
abort "Use the dedicated local acceptance port" unless port == 3111

class InstallSmokeClient
  def initialize(port)
    @port = port
    @cookies = {}
  end

  def request(method, path, fields = nil, multipart: nil)
    raise "Local paths only" unless path.start_with?("/") && !path.start_with?("//")
    request = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method).new(path)
    request["Cookie"] = @cookies.map { |key, value| "#{key}=#{value}" }.join("; ")
    request["User-Agent"] = "Mozilla/5.0 Chrome/130.0.0.0 DonghuaSyntheticAcceptance"
    request.set_form_data(fields) if fields
    request.set_form(multipart, "multipart/form-data") if multipart
    response = Net::HTTP.start("127.0.0.1", @port, nil, open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
    response.body.force_encoding(Encoding::UTF_8) if response["Content-Type"].to_s.include?("text/html")
    response.get_fields("Set-Cookie").to_a.each do |cookie|
      key, value = cookie.split(";", 2).first.split("=", 2)
      @cookies[key] = value
    end
    raise "HTTP #{response.code} at #{path}" unless (200..399).cover?(response.code.to_i)
    response
  end

  def token(response)
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content") || raise("CSRF token missing")
  end

  def location(response)
    uri = URI(response.fetch("Location"))
    raise "Redirect escaped local server" if uri.host && (uri.host != "127.0.0.1" || uri.port != @port)
    uri.host ? uri.request_uri : uri.to_s
  end
end

client = InstallSmokeClient.new(port)
first = client.request(:get, "/setup/new")
raise "Candidate is not a fresh installation" unless first.code == "200" && first.body.include?("创建系统管理员")
password = SecureRandom.hex(24)
signup = client.request(:post, "/setup", {
  "authenticity_token" => client.token(first), "user[name]" => "全新安装合成管理员",
  "user[email]" => "clean-install@example.test", "user[password]" => password, "user[password_confirmation]" => password
})
dashboard = client.request(:get, client.location(signup))
raise "Bootstrap did not authenticate" unless dashboard.body.include?("全新安装合成管理员")
form = client.request(:get, "/projects/new")
created = client.request(:post, "/projects", { "authenticity_token" => client.token(form), "project[code]" => "CLEAN-INSTALL-SYNTHETIC", "project[name]" => "独立目录端到端验收项目", "project[project_type]" => "tender_agency", "project[status]" => "active" })
project_path = client.location(created)
form = client.request(:get, "#{project_path}/fees/new")
client.request(:post, "#{project_path}/fees", { "authenticity_token" => client.token(form), "fee[fee_type]" => "agency", "fee[receivable]" => "123.45", "fee[received]" => "23.45", "fee[invoice_status]" => "not_issued" })
project = client.request(:get, project_path)
raise "Project/fee persistence failed" unless project.body.include?("独立目录端到端验收项目") && project.body.include?("100.00")
form = client.request(:get, "#{project_path}/project_documents/new")
document_path = nil
Tempfile.create([ "synthetic-original", ".txt" ]) do |file|
  file.binmode
  file.write("Synthetic clean-install original; not client evidence.")
  file.rewind
  uploaded = client.request(:post, "#{project_path}/project_documents", multipart: [
    [ "authenticity_token", client.token(form) ], [ "project_document[category]", "tender" ],
    [ "project_document[file]", file, { filename: "synthetic-original.txt", content_type: "text/plain" } ]
  ])
  document_path = client.location(uploaded)
end
detail = client.request(:get, document_path)
download = client.request(:get, "#{document_path}/download")
raise "Original byte round trip failed" unless download.body == "Synthetic clean-install original; not client evidence."
client.request(:delete, "/session", { "authenticity_token" => client.token(detail) })
blocked = client.request(:get, "#{document_path}/download")
raise "Anonymous download was not blocked" unless blocked.code == "302" && client.location(blocked) == "/session/new"
login = client.request(:get, "/session/new")
client.request(:post, "/session", { "authenticity_token" => client.token(login), "email" => "clean-install@example.test", "password" => password })
raise "Login after logout failed" unless client.request(:get, project_path).body.include?("独立目录端到端验收项目")
raise "Bootstrap remained available after setup" unless client.request(:get, "/setup/new").code == "302"
puts({ http: "passed", csrf: "real_form_tokens", bootstrap: "passed", project_and_fee: "persisted", original_upload_download: "byte_equal", anonymous_download: "blocked", logout_login: "passed", second_bootstrap: "blocked", project_path: project_path, document_path: document_path }.to_json)

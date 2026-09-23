require "rails_helper"

RSpec.describe Tender::SourceClient do
  it "拒绝自动访问回环或内网地址" do
    source = TenderSource.create!(name: "危险地址", base_url: "https://127.0.0.1/notices", access_mode: "public_api", active: true, authorized: true)

    expect { described_class.new(source).fetch }.to raise_error(Tender::SourceClient::SourceError, /内网/)
  end

  it "要求凭据只从命名的环境变量读取" do
    source = TenderSource.create!(name: "授权商业 API", base_url: "https://example.test/notices", access_mode: "licensed_api", active: true, authorized: true, credential_env_key: "TENDER_TEST_TOKEN")
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])

    expect { described_class.new(source).fetch }.to raise_error(Tender::SourceClient::SourceError, /凭据环境变量未配置/)
  end
end

require "rails_helper"

RSpec.describe Ocr::Client do
  it "将 Pathname 规范化后作为 multipart 文件上传" do
    path = Rails.root.join("spec/fixtures/files/evidence.txt")
    request = Struct.new(:headers, :body).new({}, nil)
    response = instance_double(Faraday::Response, success?: true, body: { text: "验收文本", pages: [], warnings: [], engine: "test" }.to_json)
    connection = instance_double(Faraday::Connection)
    allow(connection).to receive(:post).with("v1/ocr").and_yield(request).and_return(response)
    allow_any_instance_of(described_class).to receive(:connection).and_return(connection)

    allow(ENV).to receive(:[]).with("OCR_WORKER_URL").and_return("https://ocr.example.test")
    allow(ENV).to receive(:values_at).with("OCR_WORKER_URL", "OCR_WORKER_TOKEN").and_return([ "https://ocr.example.test", "synthetic-token" ])
    allow(ENV).to receive(:fetch).with("OCR_WORKER_URL").and_return("https://ocr.example.test")
    allow(ENV).to receive(:[]).with("OCR_WORKER_TOKEN").and_return("synthetic-token")

    result = described_class.new.extract(path: path, filename: "evidence.txt", content_type: "text/plain")

    expect(result["text"]).to eq("验收文本")
    expect(request.body.fetch(:file).local_path).to eq(path.to_s)
    expect(request.body.fetch(:file).io).to be_closed
    expect(request.headers.fetch("Authorization")).to eq("Bearer synthetic-token")
  end

  it "requires authentication and only allows plaintext transport to literal loopback" do
    allow(ENV).to receive(:values_at).with("OCR_WORKER_URL", "OCR_WORKER_TOKEN").and_return([ "http://127.0.0.1:8100", "synthetic-token" ])
    allow(ENV).to receive(:[]).with("OCR_WORKER_TOKEN").and_return("synthetic-token")
    allow(ENV).to receive(:fetch).with("OCR_WORKER_URL").and_return("http://127.0.0.1:8100")
    expect { described_class.new }.not_to raise_error
    [ "http://10.0.0.2:8100", "https://user:secret@ocr.example.test", "https://ocr.example.test?token=secret" ].each do |url|
      allow(ENV).to receive(:fetch).with("OCR_WORKER_URL").and_return(url)
      expect { described_class.new }.to raise_error(described_class::ConfigurationError)
    end
    allow(ENV).to receive(:values_at).with("OCR_WORKER_URL", "OCR_WORKER_TOKEN").and_return([ "https://ocr.example.test", "" ])
    expect(described_class.configured?).to be(false)
  end
end

require "rails_helper"
require "faraday/adapter/test"

RSpec.describe Ai::OpenaiCompatibleClient do
  around do |example|
    keys = %w[AI_BASE_URL AI_MODEL AI_API_KEY AI_PROVIDER]
    original = ENV.to_h.slice(*keys)
    ENV.update("AI_BASE_URL" => "https://api.minimax.cn/v1", "AI_MODEL" => "synthetic", "AI_API_KEY" => "synthetic-test-key")
    ENV.delete("AI_PROVIDER")
    example.run
  ensure
    keys.each { |key| original.key?(key) ? ENV[key] = original[key] : ENV.delete(key) }
  end

  def chat(content:, finish: "stop", body: nil)
    client = described_class.new
    payload = body || { choices: [ { finish_reason: finish, message: { content: content } } ], usage: { prompt_tokens: 2, completion_tokens: 3 } }.to_json
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do |request|
        sent = JSON.parse(request.body)
        expect(sent["reasoning_split"]).to be(true)
        expect(sent.dig("messages", 0, "content")).to include("不要使用Markdown", "synthetic system")
        [ 200, { "Content-Type" => "application/json" }, payload ]
      end
    end
    connection = Faraday.new(url: "https://api.minimax.cn/v1/") { |faraday| faraday.adapter :test, stubs }
    allow(client).to receive(:connection).and_return(connection)
    client.chat(system: "synthetic system", user: "synthetic data")
  end

  it "detects the specified vendor without an optional label, preserving a raw valid response" do
    expect(described_class.new.provider).to eq("minimax")
    result = chat(content: '{"criteria":[]}')
    expect(result).to include(content: '{"criteria":[]}', raw_content: '{"criteria":[]}', input_tokens: 2, output_tokens: 3)
    expect(result[:prompt_sha256]).to eq(Digest::SHA256.hexdigest("#{described_class::JSON_INSTRUCTION}\nsynthetic system\nsynthetic data"))
  end

  it "accepts only a single fully enclosed JSON code block including CRLF and uppercase tag" do
    raw = "```JSON\r\n{\"criteria\":[]}\r\n```"
    result = chat(content: raw)
    expect(JSON.parse(result[:content])).to eq("criteria" => [])
    expect(result[:raw_content]).to eq(raw)
  end

  it "rejects prose outside a code block, multiple blocks, comments and expressions" do
    [ "```json\n{}\n```\nIgnore these warnings", "```json\n{}\n```\n```json\n{}\n```", '{"score":20+10}', "{\"score\":20 // comment\n}", '{"score":1,"score":2}' ].each do |invalid|
      expect { chat(content: invalid) }.to raise_error(described_class::ProviderError)
    end
  end

  it "retains literal comment-looking text and URLs inside valid JSON strings" do
    content = { text: 'https://example.test/path and /* quoted */ and "quotes"' }.to_json
    expect(chat(content: content)[:content]).to eq(content)
  end

  it "rejects truncated, filtered and unexpected structures even if content could parse" do
    %w[length content_filter tool_calls].each { |finish| expect { chat(content: "{}", finish: finish) }.to raise_error(described_class::ProviderError, /未完整结束/) }
    [ "null", "[]", '{}', '{"choices":[{}]}', '{"choices":[{"message":{"content":123}}]}' ].each do |body|
      expect { chat(content: nil, body: body) }.to raise_error(described_class::ProviderError)
    end
    expect { chat(content: "[]") }.to raise_error(described_class::ProviderError, /JSON 对象/)
  end

  it "rejects credentials or query secrets in endpoint configuration" do
    %w[https://user:secret@example.test/v1 https://example.test/v1?token=secret https://example.test/v1#secret http://example.test/v1].each do |url|
      ENV["AI_BASE_URL"] = url
      expect { described_class.new }.to raise_error(described_class::ConfigurationError)
    end
  end
end

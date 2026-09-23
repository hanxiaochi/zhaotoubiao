# A single synthetic request. Only protocol metadata is printed; no prompts,
# returned content or authorization headers are logged. Syntax diagnostics retain
# punctuation only, replacing words and digits before printing.
abort "Explicit synthetic diagnostic required" unless ENV["SYNTHETIC_AI_DIAGNOSTIC"] == "1" && Rails.env.test?
client = Ai::OpenaiCompatibleClient.new
connection = client.send(:connection)
original_post = connection.method(:post)
connection.define_singleton_method(:post) do |*arguments, &block|
  response = original_post.call(*arguments, &block)
  begin
    body = JSON.parse(response.body)
    message = body.dig("choices", 0, "message")
    content = message.is_a?(Hash) ? message["content"] : nil
    parsed_type = begin
      JSON.parse(content.to_s).class.name
    rescue JSON::ParserError
      "not_json"
    end
    fenced = content.to_s.strip.match(/\A```(?:json)?[ \t]*\r?\n(.*?)\r?\n```\z/mi)
    fenced_type = begin
      fenced ? JSON.parse(fenced[1]).class.name : "no_anchored_fence"
    rescue JSON::ParserError
      "invalid_fenced_json"
    end
    legacy_block = content.to_s.strip.scan(/```(?:json)?\s*\n(.*?)\n```/m).first&.first
    legacy_error = nil
    legacy_type = begin
      legacy_block ? JSON.parse(legacy_block).class.name : "no_legacy_block"
    rescue JSON::ParserError => error
      legacy_error = error.message.gsub(/[\p{L}\p{N}]/, "x").first(180)
      "invalid_json"
    end
    puts({ http_status: response.status, body_type: body.class.name,
      message_keys: message.is_a?(Hash) ? message.keys : [], content_type: content.class.name,
      content_bytes: content.to_s.bytesize, content_json_type: parsed_type,
      starts_with_fence: content.to_s.strip.start_with?("```"), contains_think_tag: content.to_s.include?("<think>"),
      fence_count: content.to_s.scan("```").size,
      old_fence_matches: content.to_s.strip.scan(/```(?:json)?\s*\n(.*?)\n```/m).size,
      anchored_fence_json_type: fenced_type,
      legacy_block_json_type: legacy_type, syntax_punctuation: legacy_error,
      opening_codepoints: content.to_s.strip.codepoints.first(10), closing_codepoints: content.to_s.strip.codepoints.last(6),
      finish_reason: body.dig("choices", 0, "finish_reason"), provider_status_code: body.dig("base_resp", "status_code") }.to_json)
  rescue JSON::ParserError
    puts({ http_status: response.status, outer_json: false, bytes: response.body.to_s.bytesize }.to_json)
  end
  response
end
begin
  result = client.chat(system: Ai::PromptBuilder::BID_SYSTEM_PROMPT, user: "合成测试项目，无真实客户资料。当前评分点：方案完整性20分。没有原文件和证明资料，只列待核事项。")
  puts({ client_parse_success: true, input_tokens: result[:input_tokens], output_tokens: result[:output_tokens] }.to_json)
rescue Ai::OpenaiCompatibleClient::ProviderError
  puts({ client_parse_success: false }.to_json)
  exit 1
end

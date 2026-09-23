module Ai
  class OpenaiCompatibleClient
    class ConfigurationError < StandardError; end
    class ProviderError < StandardError; end

    JSON_INSTRUCTION = "必须只返回一个符合标准JSON语法的对象。不要使用Markdown代码块、注释、思考过程或对象外解释。字符串内换行必须转义，数字不得写成算式。缺失信息按任务要求返回null或数组条目，不编造。".freeze

    attr_reader :model, :provider

    def self.configured?
      ENV.values_at("AI_BASE_URL", "AI_MODEL", "AI_API_KEY").all?(&:present?)
    end

    def initialize
      raise ConfigurationError, "AI 服务尚未配置" unless self.class.configured?

      @base_url = ENV.fetch("AI_BASE_URL")
      @model = ENV.fetch("AI_MODEL")
      @api_key = ENV.fetch("AI_API_KEY")
      validate_base_url!
      @provider = ENV["AI_PROVIDER"].presence || (%w[api.minimax.cn api.minimax.io].include?(URI.parse(@base_url).host) ? "minimax" : "openai-compatible")
    end

    def chat(system:, user:)
      effective_system = "#{JSON_INSTRUCTION}\n#{system}"
      response = connection.post("chat/completions") do |request|
        request.headers["Authorization"] = "Bearer #{@api_key}"
        request.headers["Content-Type"] = "application/json"
        payload = {
          model: model,
          temperature: 0.1,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: effective_system },
            { role: "user", content: user }
          ]
        }
        payload[:reasoning_split] = true if provider == "minimax"
        request.body = JSON.generate(payload)
      end
      raise ProviderError, "AI 服务返回 HTTP #{response.status}" unless response.success?

      body = JSON.parse(response.body, allow_duplicate_key: false)
      raise ProviderError, "AI 服务响应结构无效" unless body.is_a?(Hash) && body["choices"].is_a?(Array) && body["choices"].first.is_a?(Hash)
      choice = body.fetch("choices").first
      raise ProviderError, "AI 服务输出未完整结束，请核对后重新生成" if choice["finish_reason"].present? && choice["finish_reason"] != "stop"
      raise ProviderError, "AI 服务响应结构无效" unless choice["message"].is_a?(Hash)
      content = body.dig("choices", 0, "message", "content")
      raise ProviderError, "AI 服务未返回有效内容" unless content.is_a?(String) && content.present?
      raw_content = content
      content = content.strip
      fence = content.match(/\A```(?:json)?[ \t]*\r?\n(.*?)\r?\n```\z/mi)
      content = fence[1] if fence
      # Ruby JSON accepts JavaScript comments; provider output must not rely on
      # that extension. Remove quoted strings before checking comment delimiters.
      raise ProviderError, "AI 服务输出包含非标准JSON注释" if content.gsub(/"(?:\\.|[^"\\])*"/m, "").match?(%r{/[/\*]})
      parsed = JSON.parse(content, allow_duplicate_key: false)
      raise ProviderError, "AI 服务输出必须是 JSON 对象" unless parsed.is_a?(Hash)

      {
        content: content,
        raw_content: raw_content,
        prompt_sha256: Digest::SHA256.hexdigest("#{effective_system}\n#{user}"),
        input_tokens: body.dig("usage", "prompt_tokens"),
        output_tokens: body.dig("usage", "completion_tokens")
      }
    rescue Faraday::Error => error
      raise ProviderError, "AI 服务连接失败（#{error.class.name.demodulize}）"
    rescue JSON::ParserError
      raise ProviderError, "AI 服务返回了无法解析的响应"
    end

    private

    def connection
      @connection ||= Faraday.new(url: normalized_base_url) do |faraday|
        faraday.options.open_timeout = 10
        faraday.options.timeout = 120
        faraday.adapter Faraday.default_adapter
      end
    end

    def normalized_base_url
      @base_url.end_with?("/") ? @base_url : "#{@base_url}/"
    end

    def validate_base_url!
      uri = URI.parse(@base_url)
      allowed = uri.is_a?(URI::HTTPS) || (Rails.env.development? && uri.is_a?(URI::HTTP) && %w[127.0.0.1 localhost].include?(uri.host))
      raise ConfigurationError, "AI_BASE_URL 必须为 HTTPS 地址" unless allowed && uri.host.present?
      raise ConfigurationError, "AI_BASE_URL 不得包含凭据、查询参数或片段" if uri.userinfo.present? || uri.query.present? || uri.fragment.present?
    rescue URI::InvalidURIError
      raise ConfigurationError, "AI_BASE_URL 格式不正确"
    end
  end
end

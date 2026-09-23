module Ocr
  class Client
    class ConfigurationError < StandardError; end
    class WorkerError < StandardError; end

    def self.configured?
      ENV.values_at("OCR_WORKER_URL", "OCR_WORKER_TOKEN").all?(&:present?)
    end

    def initialize
      raise ConfigurationError, "OCR 工作进程尚未配置" unless self.class.configured?

      @base_url = ENV.fetch("OCR_WORKER_URL")
      @token = ENV["OCR_WORKER_TOKEN"]
      validate_base_url!
    end

    def extract(path:, filename:, content_type:)
      response = File.open(path.to_s, "rb") do |file|
        connection.post("v1/ocr") do |request|
          request.headers["Authorization"] = "Bearer #{@token}" if @token.present?
          request.body = { file: Faraday::Multipart::FilePart.new(file, content_type, filename) }
        end
      end
      raise WorkerError, "OCR 工作进程返回 HTTP #{response.status}" unless response.success?

      result = JSON.parse(response.body)
      raise WorkerError, "OCR 工作进程未返回文本" unless result.is_a?(Hash) && result["text"].is_a?(String)
      pages = result["pages"]
      if pages && (!pages.is_a?(Array) || pages.any? { |page| !valid_page?(page) })
        raise WorkerError, "OCR 工作进程返回了无效的页码或图像区域"
      end

      result
    rescue Faraday::Error => error
      raise WorkerError, "OCR 工作进程连接失败（#{error.class.name.demodulize}）"
    rescue JSON::ParserError
      raise WorkerError, "OCR 工作进程返回了无法解析的响应"
    end

    private

    def valid_page?(page)
      page.is_a?(Hash) && page["page"].is_a?(Integer) && page["page"].positive? && page["text"].is_a?(String) &&
        (!page.key?("visual_review") || VisualReview.valid?(page["visual_review"]))
    end

    def connection
      @connection ||= Faraday.new(url: normalized_base_url) do |faraday|
        faraday.request :multipart
        faraday.request :url_encoded
        faraday.options.open_timeout = 5
        faraday.options.timeout = 300
        faraday.adapter Faraday.default_adapter
      end
    end

    def normalized_base_url
      @base_url.end_with?("/") ? @base_url : "#{@base_url}/"
    end

    def validate_base_url!
      uri = URI.parse(@base_url)
      loopback = uri.is_a?(URI::HTTP) && %w[127.0.0.1 ::1 [::1]].include?(uri.host)
      allowed = (uri.is_a?(URI::HTTPS) || loopback) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      raise ConfigurationError, "OCR_WORKER_URL 必须为 HTTPS 地址或本机地址" unless allowed
    rescue URI::InvalidURIError
      raise ConfigurationError, "OCR_WORKER_URL 格式不正确"
    end
  end
end

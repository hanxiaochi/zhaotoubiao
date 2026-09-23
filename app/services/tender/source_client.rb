require "ipaddr"
require "resolv"

module Tender
  class SourceClient
    class SourceError < StandardError; end

    def initialize(source)
      @source = source
    end

    def fetch
      return demo_items if @source.access_mode == "demo"
      validate_source!
      response = connection.get
      raise SourceError, "数据源返回 HTTP #{response.status}" unless response.success?

      payload = JSON.parse(response.body)
      items = payload.is_a?(Hash) ? payload["items"] : payload
      raise SourceError, "数据源响应必须为数组或包含 items 数组" unless items.is_a?(Array)
      raise SourceError, "单次同步不能超过 1000 条" if items.size > 1000

      items.map { |item| normalize_item(item) }
    rescue Faraday::Error => error
      raise SourceError, "数据源连接失败（#{error.class.name.demodulize}）"
    rescue JSON::ParserError
      raise SourceError, "数据源返回了无法解析的 JSON"
    end

    private

    def demo_items
      raise SourceError, "演示源仅可在本地开发或测试环境使用" unless Rails.env.development? || Rails.env.test?
      raise SourceError, "演示源未启用" unless @source.active? && @source.authorized?

      [
        { "external_id" => "DEMO-AUDIT-001", "title" => "【演示数据】江苏财务审计服务采购", "url" => "https://example.test/demo/audit", "region" => "江苏", "industry" => "审计服务", "deadline_at" => 5.days.from_now.iso8601 },
        { "external_id" => "DEMO-APPRAISAL-002", "title" => "【演示数据】资产评估服务采购", "url" => "https://example.test/demo/appraisal", "region" => "江苏", "industry" => "资产评估", "deadline_at" => 20.days.from_now.iso8601 }
      ].map { |item| normalize_item(item) }
    end

    def connection
      Faraday.new(url: @source.base_url, headers: request_headers) do |faraday|
        faraday.options.open_timeout = 8
        faraday.options.timeout = 30
        faraday.adapter Faraday.default_adapter
      end
    end

    def request_headers
      headers = { "Accept" => "application/json", "User-Agent" => "DonghuaAIPlatform/1.0" }
      return headers if @source.credential_env_key.blank?

      token = ENV[@source.credential_env_key]
      raise SourceError, "数据源凭据环境变量未配置" if token.blank?

      headers.merge("Authorization" => "Bearer #{token}")
    end

    def validate_source!
      raise SourceError, "数据源未启用或未确认授权" unless @source.active? && @source.authorized?
      raise SourceError, "人工导入数据源不能自动同步" if @source.access_mode == "manual_import"

      uri = URI.parse(@source.base_url)
      raise SourceError, "自动同步仅允许 HTTPS" unless uri.is_a?(URI::HTTPS) && uri.userinfo.blank?

      addresses = Resolv.getaddresses(uri.host)
      raise SourceError, "数据源域名无法解析" if addresses.empty?
      raise SourceError, "数据源地址不能指向内网" if addresses.any? { |address| unsafe_address?(address) }
    rescue URI::InvalidURIError
      raise SourceError, "数据源地址格式不正确"
    end

    def unsafe_address?(address)
      ip = IPAddr.new(address)
      ip.private? || ip.loopback? || ip.link_local? || multicast_address?(ip)
    end

    def multicast_address?(ip)
      range = ip.ipv4? ? IPAddr.new("224.0.0.0/4") : IPAddr.new("ff00::/8")
      range.include?(ip)
    end

    def normalize_item(item)
      raise SourceError, "招标信息条目必须为对象" unless item.is_a?(Hash)

      title = item["title"].to_s.strip
      url = item["url"].to_s.strip
      raise SourceError, "招标信息缺少 title 或 url" if title.blank? || url.blank?

      {
        external_id: item["external_id"].presence || Digest::SHA256.hexdigest(url),
        title: title,
        url: url,
        region: item["region"].to_s.presence,
        industry: item["industry"].to_s.presence,
        published_at: parse_time(item["published_at"]),
        deadline_at: parse_time(item["deadline_at"]),
        tags: Array(item["tags"]).map(&:to_s).map(&:strip).reject(&:blank?).first(30)
      }
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      raise SourceError, "招标信息包含无效日期"
    end
  end
end

require "uri"

module DeploymentConfiguration
  class Invalid < StandardError; end
  DATABASE_KEYS = %w[DATABASE_URL QUEUE_DATABASE_URL CACHE_DATABASE_URL CABLE_DATABASE_URL].freeze

  # Deliberate owner-only synthetic demo exception, never inferred from FORCE_SSL.
  def self.http_demo?(environment)
    environment["ALLOW_HTTP_DEMO"] == "true"
  end

  def self.validate!(environment)
    if http_demo?(environment) && environment["DEMO_DATA_ONLY"] != "true"
      raise Invalid, "HTTP demo requires DEMO_DATA_ONLY=true; do not import customer data"
    end
    if !http_demo?(environment) && environment["FORCE_SSL"] == "false"
      raise Invalid, "Disabling HTTPS requires explicit ALLOW_HTTP_DEMO=true"
    end
    missing = (DATABASE_KEYS + %w[APP_HOST APP_HOSTS S3_REGION S3_BUCKET]).select { |key| environment[key].to_s.strip.empty? }
    missing << "SECRET_KEY_BASE or RAILS_MASTER_KEY" if environment.values_at("SECRET_KEY_BASE", "RAILS_MASTER_KEY").all? { |value| value.to_s.strip.empty? }
    raise Invalid, "Missing production configuration: #{missing.join(', ')}" if missing.any?
    databases = DATABASE_KEYS.map do |key|
      begin
        uri = URI.parse(environment[key])
        unless %w[postgres postgresql].include?(uri.scheme) && uri.host && uri.path.to_s.length > 1
          raise Invalid, "#{key} must be a PostgreSQL URL with a database name"
        end
        [ uri.host.downcase, uri.port || 5432, uri.path ]
      rescue URI::InvalidURIError
        raise Invalid, "#{key} is not a valid URL"
      end
    end
    raise Invalid, "Production primary, queue, cache and cable must use distinct databases" unless databases.uniq.size == DATABASE_KEYS.size
    raise Invalid, "Production uploads must use private cloud storage" unless environment.fetch("ACTIVE_STORAGE_SERVICE", "cloud") == "cloud"
    true
  end
end

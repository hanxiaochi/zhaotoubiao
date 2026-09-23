module Audit
  class Recorder
    SENSITIVE_KEYS = %w[password password_digest api_key token secret output ocr_text content body].freeze

    def self.call(action:, record:, before_data: nil, after_data: nil)
      AuditEvent.create!(
        actor: Current.user,
        action: action,
        record_type: record.class.name,
        record_id: record.id,
        record_public_id: record.respond_to?(:public_id) ? record.public_id : nil,
        before_data: scrub(before_data),
        after_data: scrub(after_data || record.attributes),
        ip_address: Current.ip_address,
        request_id: Current.request_id,
        occurred_at: Time.current
      )
    end

    def self.scrub(data)
      return if data.nil?

      data.to_h.transform_keys(&:to_s).except(*SENSITIVE_KEYS)
    end
    private_class_method :scrub
  end
end

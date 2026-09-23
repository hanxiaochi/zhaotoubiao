class Current < ActiveSupport::CurrentAttributes
  attribute :user, :request_id, :ip_address
end

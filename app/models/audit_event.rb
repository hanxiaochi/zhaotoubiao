class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  validates :action, :record_type, :occurred_at, presence: true
  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end

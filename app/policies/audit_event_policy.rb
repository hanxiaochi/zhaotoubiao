class AuditEventPolicy < ApplicationPolicy
  def index? = user.admin? || user.allowed?("audit.view")
end

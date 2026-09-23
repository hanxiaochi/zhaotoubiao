class RolePolicy < ApplicationPolicy
  def index? = user.admin?
  def create? = user.admin?
  def update? = user.admin? && record.code != "admin"
end

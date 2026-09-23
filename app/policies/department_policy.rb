class DepartmentPolicy < ApplicationPolicy
  def index? = user.admin?
  def create? = user.admin?
  def update? = user.admin?
end

class UserPolicy < ApplicationPolicy
  def index? = user.admin?
  def show? = user.admin? || user == record
  def create? = user.admin?
  def update? = user.admin?
end

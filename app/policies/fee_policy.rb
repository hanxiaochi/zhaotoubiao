class FeePolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = ProjectPolicy.new(user, record.project).update?
  def update? = create?
end

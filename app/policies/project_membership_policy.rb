class ProjectMembershipPolicy < ApplicationPolicy
  def create? = ProjectPolicy.new(user, record.project).update?
  def update? = create?
  def destroy? = create?
end

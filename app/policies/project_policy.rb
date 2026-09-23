class ProjectPolicy < ApplicationPolicy
  def index? = true
  def show? = accessible?
  def create? = user.admin? || user.allowed?("projects.manage")
  def update? = accessible? && (user.admin? || record.owner_id == user.id || user.allowed?("projects.manage"))

  private

  def accessible?
    user.admin? || record.owner_id == user.id || record.project_memberships.exists?(user_id: user.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.admin?

      memberships = ProjectMembership.where(user_id: user.id).select(:project_id)
      scope.where(owner_id: user.id).or(scope.where(id: memberships))
    end
  end
end

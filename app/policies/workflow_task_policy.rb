class WorkflowTaskPolicy < ApplicationPolicy
  def index? = true
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = ProjectPolicy.new(user, record.project).update?
  def decide?
    return false unless show?
    return false if record.superseded?
    return false if record.claim_gate? && (!record.claim_stage_open? || !record.claim_basis_current? || !record.status.in?(%w[pending active]))
    if record.countersign?
      record.status.in?(%w[pending active]) && record.workflow_signatures.exists?(user_id: user.id, status: "pending")
    else
      record.status.in?(%w[pending active returned]) && (user.admin? || record.assignee_id == user.id || record.project.owner_id == user.id)
    end
  end

  def restart? = create? && record.restartable?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.admin?

      scope.where(project_id: ProjectPolicy::Scope.new(user, Project).resolve.select(:id))
    end
  end
end

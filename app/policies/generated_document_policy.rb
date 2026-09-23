class GeneratedDocumentPolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = ProjectPolicy.new(user, record.project).update?
  def update? = create? && record.status.in?(%w[draft rejected])
  def submit? = update?
  def approve? = show? && record.status == "pending_review" && (user.admin? || user.allowed?("documents.approve"))
  def reject? = approve?
end

class AiRunPolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = show? && record.editable_source? && ProjectPolicy.new(user, record.project).update?
  def approve? = reject? && record.editable_source?
  def reject? = show? && record.status == "pending_review" && (user.admin? || user.allowed?("ai.review"))
end

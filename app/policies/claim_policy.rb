class ClaimPolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = ProjectPolicy.new(user, record.project).update?
  def update? = !record.status.in?(%w[approved rejected]) && (create? || (show? && record.created_by_id == user.id))
  def resubmit? = update? && record.status == "supplement_required"
  def review? = show? && !record.status.in?(%w[approved rejected supplement_required]) && ClaimReviewFlow.new(record, user).allowed?
end

class BidAnalysisPolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = ProjectPolicy.new(user, record.project).update?
  def update? = create?
  def review? = show? && (user.admin? || user.allowed?("bids.review"))
end

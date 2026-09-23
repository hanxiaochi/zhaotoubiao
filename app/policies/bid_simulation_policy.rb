class BidSimulationPolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = show? && ProjectPolicy.new(user, record.project).update?
end

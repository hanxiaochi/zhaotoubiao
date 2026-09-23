class TenderSourcePolicy < ApplicationPolicy
  def index? = user.admin? || user.allowed?("tenders.sources")
  def create? = index?
  def update? = index?
end

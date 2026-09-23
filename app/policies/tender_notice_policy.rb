class TenderNoticePolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = user.admin? || user.allowed?("tenders.manage")
  def update? = create?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end

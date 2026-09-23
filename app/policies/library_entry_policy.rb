class LibraryEntryPolicy < ApplicationPolicy
  def index? = user.admin? || user.allowed?("library.view") || user.allowed?("library.manage")
  def show? = index?
  def download? = show?
  def create? = user.admin? || user.allowed?("library.manage")
  def update? = create?

  class Scope < ApplicationPolicy::Scope
    def resolve
      LibraryEntryPolicy.new(user, LibraryEntry).index? ? scope.all : scope.none
    end
  end
end

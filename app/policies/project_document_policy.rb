class ProjectDocumentPolicy < ApplicationPolicy
  def show? = ProjectPolicy.new(user, record.project).show?
  def create? = ProjectPolicy.new(user, record.project).update?
  def update? = record.status != "archived" && create?
  def download? = show?
  def archive? = update?
end

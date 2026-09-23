class WorkflowSignature < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :user
  validates :user_id, uniqueness: { scope: :workflow_task_id }
  validates :status, inclusion: { in: %w[pending approved rejected returned] }
  validate :user_belongs_to_project

  private

  def user_belongs_to_project
    project = workflow_task&.project
    return if project.blank? || user.blank?
    eligible = user.active? && (project.owner_id == user_id || project.project_memberships.where.not(membership_role: "observer").exists?(user_id: user_id))
    errors.add(:user, "必须是本项目的有效办理成员") unless eligible
  end
end

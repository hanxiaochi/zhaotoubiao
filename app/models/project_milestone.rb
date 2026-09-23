class ProjectMilestone < ApplicationRecord
  include HasPublicId
  has_paper_trail

  STATUSES = %w[pending active completed delayed cancelled].freeze

  belongs_to :project
  belongs_to :owner, class_name: "User", optional: true

  validates :title, :stage, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :owner_belongs_to_project

  def overdue?(reference_date = Date.current)
    due_on.present? && due_on < reference_date && !status.in?(%w[completed cancelled])
  end

  private

  def owner_belongs_to_project
    return if owner.blank? || project.blank?
    return if project.owner_id == owner_id || project.project_memberships.exists?(user_id: owner_id)

    errors.add(:owner, "必须是项目负责人或项目成员")
  end
end

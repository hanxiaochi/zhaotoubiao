class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user

  validates :user_id, uniqueness: { scope: :project_id }
  validates :membership_role, inclusion: { in: %w[member lawyer manager owner observer] }
end

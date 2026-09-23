class WorkflowEvent < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :actor, class_name: "User"

  validates :decision, :comment, presence: true
  validates :decision, inclusion: { in: %w[approve reject return complete comment] }
end

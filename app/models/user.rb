class User < ApplicationRecord
  include HasPublicId

  has_secure_password
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships
  has_many :notifications, dependent: :destroy
  has_many :assigned_workflow_tasks, class_name: "WorkflowTask", foreign_key: :assignee_id, dependent: :nullify
  belongs_to :department, optional: true

  normalizes :email, with: ->(value) { value.strip.downcase }

  validates :name, presence: true, length: { maximum: 64 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }
  validates :status, inclusion: { in: %w[active disabled] }

  scope :active, -> { where(status: "active") }

  def admin?
    roles.exists?(code: "admin")
  end

  def active?
    status == "active"
  end

  def allowed?(permission)
    admin? || roles.any? { |role| role.permissions.include?(permission.to_s) }
  end
end

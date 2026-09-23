class Project < ApplicationRecord
  include HasPublicId
  has_paper_trail

  TYPES = %w[bankruptcy tender_agency bid engineering_audit asset_appraisal financial_audit].freeze
  STATUSES = %w[draft active reviewing completed archived].freeze

  belongs_to :department, optional: true
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :archived_by, class_name: "User", optional: true
  has_many :project_memberships, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user
  has_many :intake_items, dependent: :destroy
  has_many :project_documents, dependent: :destroy
  has_many :assets, dependent: :destroy
  has_many :claims, dependent: :destroy
  has_many :workflow_tasks, dependent: :destroy
  has_many :fees, dependent: :destroy
  has_many :bid_analyses, dependent: :destroy
  has_many :generated_documents, dependent: :destroy
  has_many :ai_runs, dependent: :destroy
  has_many :project_milestones, dependent: :destroy
  has_many :claim_checklists, dependent: :destroy
  store_accessor :metadata, :client_name, :project_category, :tender_method, :budget_amount

  validates :code, :name, :project_type, :status, presence: true
  validates :code, uniqueness: true
  validates :project_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validate :due_date_not_before_start_date
  validates :budget_amount, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
  validates :archive_reason, presence: true, if: :archived?

  private

  def archived?
    status == "archived"
  end

  def due_date_not_before_start_date
    return if start_date.blank? || due_date.blank? || due_date >= start_date

    errors.add(:due_date, "不能早于开始日期")
  end
end

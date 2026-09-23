class WorkflowTask < ApplicationRecord
  include HasPublicId

  belongs_to :project
  belongs_to :record, polymorphic: true
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :replaces_task, class_name: "WorkflowTask", optional: true
  has_one :replacement_task, class_name: "WorkflowTask", foreign_key: :replaces_task_id, dependent: :restrict_with_error
  has_many :workflow_events, dependent: :destroy
  has_many :workflow_signatures, dependent: :destroy, autosave: true
  validates_associated :workflow_signatures
  before_validation :capture_claim_gate, on: :create
  validate :valid_claim_gate, on: :create
  validates :restart_reason, presence: true, if: :replaces_task_id?
  scope :current, -> { where.not(id: WorkflowTask.where.not(replaces_task_id: nil).select(:replaces_task_id)) }

  def claim_gate? = record_type == "Claim" && claim_review_stage.present?
  def superseded? = persisted? && WorkflowTask.exists?(replaces_task_id: id)
  def record_ref = "#{record_type}:#{record&.public_id}"

  def claim_basis_current?
    claim_gate? && claim_basis_sha256.present? && claim_basis_sha256 == ClaimWorkflowGate.basis(record)
  end

  def claim_stage_open?
    claim_gate? && record.review_stage == claim_review_stage && !record.status.in?(%w[approved rejected supplement_required])
  end

  def restartable?
    claim_stage_open? && !superseded? && (status.in?(%w[returned rejected]) || !claim_basis_current?)
  end

  def countersign?
    workflow_signatures.exists?
  end

  validates :stage, :status, presence: true
  validates :status, inclusion: { in: %w[pending active approved rejected returned cancelled] }
  validate :record_belongs_to_project
  validate :assignee_belongs_to_project

  def pending_recipients
    countersign? ? workflow_signatures.where(status: "pending").includes(:user).map(&:user) : [ assignee || project.owner ].compact
  end

  def self.pending_for(user, projects:)
    available = current.where(project_id: projects.select(:id), status: %w[pending active])
    single = available.where.not(id: WorkflowSignature.select(:workflow_task_id))
    assigned = single.where(assignee: user)
    fallback = single.where(assignee_id: nil, project_id: projects.where(owner: user).select(:id))
    signatures = available.where(id: WorkflowSignature.where(user: user, status: "pending").select(:workflow_task_id))
    assigned.or(fallback).or(signatures)
  end

  def overdue?(reference_time = Time.current)
    due_at.present? && due_at < reference_time && status.in?(%w[pending active])
  end

  private

  def capture_claim_gate
    return unless record.is_a?(Claim)
    self.claim_review_stage = record.review_stage
    self.claim_basis_sha256 = ClaimWorkflowGate.basis(record)
  end

  def valid_claim_gate
    if record.is_a?(Claim) && !claim_stage_open?
      errors.add(:record, "债权终审、驳回或待补正时不能新建审核任务")
    end
    if replaces_task && (replaces_task.record != record || !replaces_task.restartable?)
      errors.add(:replaces_task, "必须是当前债权层级中可重新发起的原任务")
    end
  end

  def assignee_belongs_to_project
    return if assignee.blank? || project.blank?
    valid = assignee.active? && (project.owner_id == assignee_id || project.project_memberships.where.not(membership_role: "observer").exists?(user_id: assignee_id))
    errors.add(:assignee, "必须是本项目的有效办理成员") unless valid
  end

  def record_belongs_to_project
    return if record.blank? || project.blank?

    record_project_id = record.is_a?(Project) ? record.id : record.try(:project_id)
    errors.add(:record, "必须属于同一项目") unless record_project_id == project.id
  end
end

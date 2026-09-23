class AiRun < ApplicationRecord
  include HasPublicId

  TASK_TYPES = %w[bid_analysis claim_analysis document_summary draft_document bid_simulation].freeze

  belongs_to :project
  belongs_to :record, polymorphic: true
  belongs_to :requested_by, class_name: "User"
  belongs_to :reviewed_by, class_name: "User", optional: true
  before_validation :capture_source_fingerprint, on: :create

  validates :task_type, :status, presence: true
  validates :task_type, inclusion: { in: TASK_TYPES }
  validates :status, inclusion: { in: %w[queued running completed failed pending_review approved rejected] }
  validates :review_note, :reviewed_by, :reviewed_at, presence: true, if: -> { status.in?(%w[approved rejected]) }

  def terminal?
    status.in?(%w[failed approved rejected])
  end

  def source_current?
    source_fingerprint.present? && source_fingerprint == Ai::SourceFingerprint.call(record)
  end

  def editable_source?
    case record
    when Claim then !record.status.in?(%w[approved rejected])
    when GeneratedDocument then record.status.in?(%w[draft rejected]) && record.bid_basis_current?
    when BidAnalysis then !record.status.in?(%w[processing])
    when BidSimulation then record.status == "draft" && record.current_basis?
    else false
    end
  end

  private

  def capture_source_fingerprint
    self.source_fingerprint ||= Ai::SourceFingerprint.call(record) if record&.persisted?
  end
end

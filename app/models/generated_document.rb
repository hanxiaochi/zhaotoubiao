class GeneratedDocument < ApplicationRecord
  include HasPublicId
  has_paper_trail
  KINDS = { "tender_document" => "招标文件", "bid_technical" => "技术标", "bid_commercial" => "商务标", "audit_workpaper" => "审计底稿", "appraisal_workpaper" => "评估底稿", "general" => "通用文稿" }.freeze

  belongs_to :project
  belongs_to :created_by, class_name: "User"
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :bid_analysis, optional: true
  attr_accessor :refresh_bid_basis
  before_validation :capture_bid_basis
  validate :valid_bid_basis

  def bid_basis_current?
    !bid_analysis_id? || bid_basis_snapshot == BidDraftBasis.snapshot(bid_analysis)
  end

  validates :kind, :title, :content, :status, presence: true
  validates :kind, inclusion: { in: %w[tender_document bid_technical bid_commercial audit_workpaper appraisal_workpaper general] }
  validates :status, inclusion: { in: %w[draft pending_review approved rejected archived] }
  validates :review_note, presence: true, if: -> { status.in?(%w[approved rejected]) }
  validates :approved_by, :approved_at, presence: true, if: -> { status == "approved" }

  private

  def capture_bid_basis
    if new_record? || bid_analysis_id_changed? || ActiveModel::Type::Boolean.new.cast(refresh_bid_basis)
      self.bid_basis_snapshot = BidDraftBasis.snapshot(bid_analysis)
    end
  end

  def valid_bid_basis
    if bid_analysis_id? && (!bid_analysis || bid_analysis.project_id != project_id)
      errors.add(:bid_analysis, "必须属于当前项目")
    end
    if bid_analysis && !kind.in?(%w[bid_technical bid_commercial])
      errors.add(:bid_analysis, "仅技术标或商务标可关联投标分析")
    end
    if status.in?(%w[pending_review approved]) && !bid_basis_current?
      errors.add(:bid_analysis, "起草依据已变化，请退回草稿、刷新依据并核对正文后重新提交")
    end
  end
end

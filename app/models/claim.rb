class Claim < ApplicationRecord
  include HasPublicId
  has_paper_trail

  STATUSES = %w[received initial_review supplement_required substantive_review pending_approval approved rejected].freeze
  CLAIM_TYPES = %w[unknown secured employee tax priority ordinary subordinated].freeze

  belongs_to :project
  belongs_to :created_by, class_name: "User"
  has_many :claim_materials, dependent: :destroy
  has_many :claim_reviews, dependent: :destroy
  has_many :claim_supplements, dependent: :destroy

  def supplement_issues
    return [ "尚未配置债权材料核验清单" ] unless claim_materials.exists?
    claim_materials.flat_map { |material| material.review_issues.map { |issue| "#{material.material_type}：#{issue}" } }
  end

  validates :creditor_name, :currency, :claimed_type, :status, presence: true
  validates :claim_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :claimed_type, inclusion: { in: CLAIM_TYPES }
  validates :recommended_type, inclusion: { in: CLAIM_TYPES }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :review_stage, inclusion: { in: ClaimReviewFlow::STAGES }
  validates :completeness_score, numericality: { in: 0..100 }, allow_nil: true
  validate :analysis_data_is_hash

  def recalculate_completeness!
    with_lock do
      applicable = claim_materials.where.not(material_requirement: "not_required")
      total = applicable.count
      score = total.zero? ? 0 : applicable.where(present: true).count.fdiv(total) * 100
      update!(completeness_score: score.round(2))
    end
  end

  private

  def analysis_data_is_hash
    errors.add(:analysis_data, "必须是结构化对象") unless analysis_data.is_a?(Hash)
  end
end

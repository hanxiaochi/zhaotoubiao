class BidScore < ApplicationRecord
  include HasPublicId
  has_paper_trail
  belongs_to :bid_analysis
  belongs_to :project_document, optional: true
  belongs_to :updated_by, class_name: "User"
  validates :criterion, :rationale, presence: true
  validates :criterion, uniqueness: { scope: :bid_analysis_id }
  validates :maximum, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :awarded, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: ->(row) { row.maximum&.finite? ? row.maximum : 0 } }
  validates :evidence_exception, presence: true, unless: :requires_evidence?
  validate :source_and_criterion

  def evidence_issues
    return [] unless requires_evidence?
    if project_document
      issues = []
      issues << "原件位置或页码未填写" if page_reference.blank?
      issues << "来源文件已归档，请核对是否仍可使用" if project_document.status == "archived"
      issues
    else
      usable = bid_analysis.bid_evidences.includes(:library_entry).where(criterion: criterion).any?(&:usable_proof?)
      usable ? [] : [ "缺少同评分点的有效证明原件（项目文件或资料库引用）" ]
    end
  end

  private

  def source_and_criterion
    if active? && !bid_analysis&.criteria&.include?(criterion)
      errors.add(:criterion, "必须是当前分析中的评分点")
    end
    if project_document && project_document.project_id != bid_analysis&.project_id
      errors.add(:project_document, "必须属于当前项目")
    end
    errors.add(:project_document, "文件不存在") if project_document_id.present? && project_document.nil?
    return unless active? && bid_analysis && maximum&.finite? && maximum > 0
    other = bid_analysis.bid_scores.where(active: true).where.not(id: id).where(criterion: bid_analysis.criteria).sum(:maximum)
    errors.add(:maximum, "当前评分点满分合计不能超过 100") if other + maximum > 100
  end
end

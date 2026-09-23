class ClaimChecklist < ApplicationRecord
  include HasPublicId
  has_paper_trail

  DEFAULT_MATERIAL_TYPES = %w[债权申报书 主体资格证明 合同 发票 付款凭证 授权委托书 证据附件].freeze

  belongs_to :project
  belongs_to :created_by, class_name: "User"

  validates :name, :claim_type, presence: true
  validates :name, uniqueness: { scope: :project_id }
  validates :claim_type, inclusion: { in: Claim::CLAIM_TYPES }
  validate :material_types_are_valid

  def applicable_to?(type)
    claim_type == "unknown" || claim_type == type
  end

  private

  def material_types_are_valid
    normalized = Array(material_types).map { |item| item.to_s.squish }.reject(&:blank?).uniq
    errors.add(:material_types, "至少填写一项材料") if normalized.empty?
    errors.add(:material_types, "单项名称不能超过 50 个字符") if normalized.any? { |item| item.length > 50 }
    errors.add(:material_types, "最多允许 30 项") if normalized.size > 30
    self.material_types = normalized
  end
end

class ClaimMaterial < ApplicationRecord
  REQUIREMENT_FIELDS = %w[material_requirement signature_requirement seal_requirement authorization_requirement].freeze
  REQUIREMENT_OPTIONS = [ [ "待确认适用规则", "undetermined" ], [ "本材料要求", "required" ], [ "不适用（须注明依据）", "not_required" ] ].freeze
  belongs_to :claim
  belongs_to :project_document, optional: true
  belongs_to :checked_by, class_name: "User", optional: true

  validates :material_type, presence: true, uniqueness: { scope: :claim_id }
  validates :extraction_confidence, numericality: { in: 0..100 }, allow_nil: true
  validates(*REQUIREMENT_FIELDS, inclusion: { in: %w[required not_required undetermined] })
  validates :requirement_note, presence: true, if: -> { REQUIREMENT_FIELDS.any? { |field| public_send(field) == "not_required" } }
  validate :document_belongs_to_claim_project
  after_commit -> { claim.recalculate_completeness! }, on: %i[create update destroy]

  def review_issues
    return [] if material_requirement == "not_required"
    issues = []
    issues << "材料是否适用尚未确认" if material_requirement == "undetermined"
    issues << "尚未收到材料" unless present?
    issues << "来源原件未关联" if present? && project_document.nil?
    issues << "来源文件已归档" if project_document&.status == "archived"
    issues << "尚未人工核验" if present? && checked_by.nil?
    { "signature" => [ "签字", signature_detected ], "seal" => [ "盖章", seal_detected ], "authorization" => [ "授权委托", authorization_complete ] }.each do |key, (label, result)|
      requirement = public_send("#{key}_requirement")
      next if requirement == "not_required"
      issues << "#{label}适用规则尚未确认" if requirement == "undetermined"
      issues << "#{label}核验未通过" if result == false
      issues << "#{label}尚未人工核验" if requirement == "required" && result.nil?
    end
    issues
  end

  private

  def document_belongs_to_claim_project
    return if project_document.blank? || claim.blank?

    errors.add(:project_document, "必须属于债权所在项目") unless project_document.project_id == claim.project_id
  end
end

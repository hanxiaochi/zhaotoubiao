class Asset < ApplicationRecord
  include HasPublicId
  has_paper_trail

  attr_accessor :change_reason

  belongs_to :project
  belongs_to :updated_by, class_name: "User"
  has_many :asset_versions, dependent: :destroy

  validates :asset_code, :name, :category, :disposal_status, presence: true
  validates :asset_code, uniqueness: { scope: :project_id }
  validates :appraisal_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :source_reference, length: { maximum: 255 }
  validates :description, length: { maximum: 2000 }

  def capture_version!(change_reason:, actor:)
    asset_versions.create!(
      changed_by: actor,
      change_reason: change_reason,
      appraisal_value: appraisal_value,
      snapshot: attributes.except("created_at", "updated_at")
    )
  end

  def risk_flags = AssetRiskAnalyzer.call(self)
end

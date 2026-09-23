class ProjectDocument < ApplicationRecord
  include HasPublicId
  has_paper_trail
  has_one_attached :file

  belongs_to :project
  belongs_to :uploaded_by, class_name: "User"
  has_many :claim_materials, dependent: :nullify

  validates :category, :status, :original_filename, presence: true
  validates :status, inclusion: { in: %w[uploaded processing reviewed archived] }
  validates :sha256, uniqueness: { scope: :project_id, message: "对应的原件已存在，请到文件档案查看，勿重复上传" }, allow_nil: true
  validates :byte_size, numericality: { less_than_or_equal_to: 50.megabytes }, allow_nil: true
  validate :file_is_attached
  validates :ocr_status, inclusion: { in: %w[pending queued processing completed failed not_required] }
  validates :analysis_status, inclusion: { in: %w[pending queued processing completed failed reviewed] }

  def extracted_fields = metadata.fetch("extracted_fields", {})
  def classification = metadata["classification"]
  def classification_confidence = metadata["classification_confidence"]
  def review_indicators = metadata.fetch("review_indicators", {})

  private

  def file_is_attached
    errors.add(:file, "必须选择文件") unless file.attached?
  end
end

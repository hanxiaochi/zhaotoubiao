class LibraryEntry < ApplicationRecord
  include HasPublicId
  has_paper_trail
  KINDS = { "qualification" => "企业资质", "case_study" => "项目案例" }.freeze
  belongs_to :created_by, class_name: "User"
  has_many_attached :documents
  has_many :bid_evidences, dependent: :restrict_with_error
  validates :title, :organization, :description, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: %w[active archived] }
  validates :revision_number, numericality: { only_integer: true, greater_than: 0 }
  validate :dates_and_documents

  def expired? = expires_on.present? && expires_on < Date.current
  def usable? = status == "active" && !expired?

  def evidence_snapshot
    attributes.slice("public_id", "kind", "title", "organization", "reference_number", "description", "issued_on", "expires_on", "revision_number").merge(
      "documents" => documents.map { |file| { "attachment_id" => file.id, "filename" => file.filename.to_s, "checksum" => file.blob.checksum } }
    )
  end

  private

  def dates_and_documents
    errors.add(:expires_on, "不能早于签发或完成日期") if issued_on && expires_on && expires_on < issued_on
    documents.each do |file|
      errors.add(:documents, "单个文件不能超过 50 MB") if file.byte_size > IntakeItem::MAX_ATTACHMENT_SIZE
      errors.add(:documents, "文件类型不受支持") unless file.content_type.in?(IntakeItem::ALLOWED_ATTACHMENT_TYPES)
    end
  end
end

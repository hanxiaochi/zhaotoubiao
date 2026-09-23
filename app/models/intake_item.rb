class IntakeItem < ApplicationRecord
  include HasPublicId
  has_paper_trail

  MAX_ATTACHMENT_SIZE = 50.megabytes
  ALLOWED_ATTACHMENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/msword
    application/vnd.ms-excel
    image/jpeg image/png image/tiff text/plain text/csv
  ].freeze

  belongs_to :project
  belongs_to :created_by, class_name: "User"
  has_many_attached :attachments

  validates :category, :name, :status, presence: true
  validates :status, inclusion: { in: %w[pending received missing returned archived] }
  validate :attachments_are_safe

  private

  def attachments_are_safe
    attachments.each do |attachment|
      errors.add(:attachments, "单个文件不能超过 50 MB") if attachment.byte_size > MAX_ATTACHMENT_SIZE
      errors.add(:attachments, "包含不受支持的文件类型") unless attachment.content_type.in?(ALLOWED_ATTACHMENT_TYPES)
    end
  end
end

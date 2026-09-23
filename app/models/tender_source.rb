class TenderSource < ApplicationRecord
  include HasPublicId

  has_many :tender_notices, dependent: :restrict_with_error
  validates :name, :base_url, :access_mode, presence: true
  validates :access_mode, inclusion: { in: %w[public_api licensed_api manual_import demo] }
  validate :authorized_when_active
  validate :base_url_is_http
  validates :credential_env_key, format: { with: /\A[A-Z][A-Z0-9_]*\z/, message: "只能使用大写环境变量名称" }, allow_blank: true

  def syncable? = active? && authorized? && access_mode != "manual_import"

  private

  def authorized_when_active
    errors.add(:authorized, "启用前必须确认数据授权") if active? && !authorized?
  end

  def base_url_is_http
    uri = URI.parse(base_url.to_s)
    errors.add(:base_url, "必须使用 HTTP 或 HTTPS 地址") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, "格式不正确")
  end
end

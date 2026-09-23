class TenderNotice < ApplicationRecord
  include HasPublicId

  belongs_to :tender_source, optional: true
  validates :title, :url, :status, presence: true
  validates :status, inclusion: { in: %w[new tracking applied ignored expired] }
  validate :source_is_authorized
  validate :url_is_http

  private

  def source_is_authorized
    return unless tender_source && (new_record? || will_save_change_to_tender_source_id?)

    errors.add(:tender_source, "必须是已授权数据源") unless tender_source.authorized?
  end

  def url_is_http
    uri = URI.parse(url.to_s)
    errors.add(:url, "必须使用 HTTP 或 HTTPS 地址") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "格式不正确")
  end
end

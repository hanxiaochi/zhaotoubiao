class Fee < ApplicationRecord
  include HasPublicId
  has_paper_trail

  belongs_to :project
  belongs_to :created_by, class_name: "User"

  TYPE_LABELS = { "registration" => "报名费", "expert" => "专家费", "agency" => "代理服务费", "other" => "其他费用" }.freeze
  INVOICE_LABELS = { "not_issued" => "未开票", "requested" => "申请中", "issued" => "已开票", "not_required" => "无需开票" }.freeze

  validates :fee_type, :invoice_status, presence: true
  validates :fee_type, inclusion: { in: %w[registration expert agency other] }
  validates :invoice_status, inclusion: { in: INVOICE_LABELS.keys }
  validates :receivable, :received, numericality: { greater_than_or_equal_to: 0 }

  def outstanding
    [ receivable - received, 0 ].max
  end

  def overpaid
    [ received - receivable, 0 ].max
  end

  def payment_status
    return "overpaid" if received > receivable
    return "paid" if receivable.positive? && received == receivable
    return "partial" if received.positive?

    "unpaid"
  end
end

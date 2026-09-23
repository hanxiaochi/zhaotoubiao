class BidAnalysis < ApplicationRecord
  include HasPublicId
  has_paper_trail

  belongs_to :project
  has_many :bid_evidences, dependent: :restrict_with_error
  has_many :bid_scores, dependent: :restrict_with_error
  has_many :bid_simulations, dependent: :restrict_with_error
  belongs_to :reviewed_by, class_name: "User", optional: true
  REVIEW_SECTIONS = {
    "qualification_requirements" => "资格条件", "disqualification_clauses" => "废标条款",
    "time_nodes" => "时间节点", "suggested_tasks" => "建议待办清单"
  }.freeze
  TEXT_FIELDS = (%w[criteria risks outline] + REVIEW_SECTIONS.keys).freeze
  attr_accessor(*TEXT_FIELDS.map { |field| "#{field}_text" })

  validates :status, inclusion: { in: %w[pending processing draft pending_review reviewed failed] }
  validates :simulated_score, numericality: { in: 0..100 }, allow_nil: true
  validates :review_note, presence: true, if: -> { status == "reviewed" }
  validates :reviewed_by, :reviewed_at, presence: true, if: -> { status == "reviewed" }
  validate :structured_fields_are_arrays

  private

  def structured_fields_are_arrays
    TEXT_FIELDS.each do |field|
      value = public_send(field)
      errors.add(field, "必须是字符串条目数组") unless value.is_a?(Array) && value.all?(String)
    end
  end
end

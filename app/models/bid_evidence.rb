class BidEvidence < ApplicationRecord
  include HasPublicId
  belongs_to :bid_analysis
  belongs_to :library_entry
  belongs_to :created_by, class_name: "User"
  validates :criterion, :note, :page_reference, :source_snapshot, presence: true
  validate :criterion_belongs_to_analysis, on: :create

  def usable_proof?
    expires = source_snapshot["expires_on"]
    library_entry.usable? &&
      source_snapshot.fetch("documents", []).any? &&
      source_snapshot["revision_number"] == library_entry.revision_number &&
      (expires.blank? || Date.iso8601(expires.to_s) >= Date.current)
  rescue Date::Error
    false
  end

  private

  def criterion_belongs_to_analysis
    errors.add(:criterion, "必须选择当前分析的评分点") unless bid_analysis&.criteria&.include?(criterion)
  end
end

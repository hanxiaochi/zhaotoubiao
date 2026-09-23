class ClaimSupplement < ApplicationRecord
  belongs_to :claim
  belongs_to :submitted_by, class_name: "User"
  validates :note, :review_stage, presence: true
  validates :review_stage, inclusion: { in: ClaimReviewFlow::STAGES }
end

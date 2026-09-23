class ClaimReview < ApplicationRecord
  STAGES = ClaimReviewFlow::STAGES
  DECISIONS = %w[approve reject request_supplement].freeze

  belongs_to :claim
  belongs_to :reviewer, class_name: "User"
  before_update { throw :abort }
  before_destroy { throw :abort }

  validates :stage, :decision, :comment, presence: true
  validates :stage, inclusion: { in: STAGES }
  validates :decision, inclusion: { in: DECISIONS }
end

class SnapshotClaimReviewBasis < ActiveRecord::Migration[8.1]
  def change
    add_column :claim_reviews, :basis_sha256, :string
    add_column :claim_reviews, :evidence_snapshot, :json, null: false, default: {}
  end
end

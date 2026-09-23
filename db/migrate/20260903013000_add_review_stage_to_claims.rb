class AddReviewStageToClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :claims, :review_stage, :string, default: "initial", null: false
    add_index :claims, %i[project_id review_stage status]
  end
end

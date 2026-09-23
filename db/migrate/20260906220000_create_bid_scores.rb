class CreateBidScores < ActiveRecord::Migration[8.1]
  def change
    create_table :bid_scores do |t|
      t.string :public_id, null: false
      t.references :bid_analysis, null: false, foreign_key: true
      t.references :project_document, foreign_key: true
      t.references :updated_by, null: false, foreign_key: { to_table: :users }
      t.string :criterion, null: false
      t.decimal :maximum, precision: 7, scale: 2, null: false
      t.decimal :awarded, precision: 7, scale: 2, null: false
      t.text :rationale, null: false
      t.string :page_reference
      t.boolean :requires_evidence, null: false, default: true
      t.text :evidence_exception
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :bid_scores, :public_id, unique: true
    add_index :bid_scores, [ :bid_analysis_id, :criterion ], unique: true
    add_check_constraint :bid_scores, "maximum > 0 AND maximum <= 100 AND awarded >= 0 AND awarded <= maximum", name: "bid_scores_valid_range"
  end
end

class CreateBidSimulations < ActiveRecord::Migration[8.1]
  def change
    add_column :bid_scores, :scoring_rule, :text
    create_table :bid_simulations do |t|
      t.string :public_id, null: false
      t.references :bid_analysis, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :source, polymorphic: true, null: false
      t.string :title, null: false
      t.boolean :confirmed_complete, null: false, default: false
      t.text :source_text, null: false
      t.json :rubric, null: false, default: []
      t.string :basis_sha256, null: false
      t.string :source_title, null: false
      t.string :status, null: false, default: "draft"
      t.json :results, null: false, default: []
      t.json :warnings, null: false, default: []
      t.decimal :total_score, precision: 7, scale: 2
      t.timestamps
    end
    add_index :bid_simulations, :public_id, unique: true
  end
end

class CreateClaimSupplements < ActiveRecord::Migration[8.1]
  def change
    create_table :claim_supplements do |t|
      t.references :claim, null: false, foreign_key: true
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.text :note, null: false
      t.json :material_snapshot, null: false, default: []
      t.string :review_stage, null: false
      t.timestamps
    end
  end
end

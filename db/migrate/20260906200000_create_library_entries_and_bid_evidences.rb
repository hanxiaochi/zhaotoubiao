class CreateLibraryEntriesAndBidEvidences < ActiveRecord::Migration[8.1]
  def change
    create_table :library_entries do |t|
      t.string :public_id, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.string :organization, null: false
      t.string :reference_number
      t.text :description, null: false
      t.date :issued_on
      t.date :expires_on
      t.string :status, null: false, default: "active"
      t.integer :revision_number, null: false, default: 1
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :library_entries, :public_id, unique: true
    add_index :library_entries, [ :kind, :status ]
    create_table :bid_evidences do |t|
      t.string :public_id, null: false
      t.references :bid_analysis, null: false, foreign_key: true
      t.references :library_entry, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :criterion, null: false
      t.text :note, null: false
      t.string :page_reference, null: false
      t.json :source_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :bid_evidences, :public_id, unique: true
  end
end

class AddProjectDeliveryControls < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :archived_by, foreign_key: { to_table: :users }
    add_column :projects, :archived_at, :datetime
    add_column :projects, :archive_reason, :text

    create_table :project_milestones do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :title, null: false
      t.string :stage, null: false
      t.string :status, null: false, default: "pending"
      t.date :due_on
      t.date :completed_on
      t.references :owner, foreign_key: { to_table: :users }
      t.text :note
      t.timestamps
    end
    add_index :project_milestones, :public_id, unique: true
    add_index :project_milestones, %i[project_id status due_on]

    create_table :claim_checklists do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :claim_type, null: false, default: "unknown"
      t.json :material_types, null: false, default: []
      t.boolean :active, null: false, default: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :claim_checklists, :public_id, unique: true
    add_index :claim_checklists, %i[project_id claim_type active]
    add_index :claim_checklists, %i[project_id name], unique: true
  end
end

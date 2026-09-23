class CreateWorkflowSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_signatures do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :comment
      t.datetime :decided_at
      t.timestamps
    end
    add_index :workflow_signatures, %i[workflow_task_id user_id], unique: true
  end
end

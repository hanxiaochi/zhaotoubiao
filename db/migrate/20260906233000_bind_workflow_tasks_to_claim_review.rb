class BindWorkflowTasksToClaimReview < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_tasks, :claim_review_stage, :string
    add_column :workflow_tasks, :claim_basis_sha256, :string
    add_reference :workflow_tasks, :replaces_task, foreign_key: { to_table: :workflow_tasks }, index: { unique: true }
    add_column :workflow_tasks, :restart_reason, :text
    add_index :workflow_tasks, [ :record_type, :record_id, :claim_review_stage ], name: "index_workflow_claim_stage"
  end
end

class HardenBackgroundExecution < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :deduplication_key, :string
    add_index :notifications, :deduplication_key, unique: true
    add_column :project_documents, :ocr_attempt_token, :string
    add_index :ai_runs, [ :status, :updated_at ]
    add_index :project_documents, [ :ocr_status, :updated_at ]
  end
end

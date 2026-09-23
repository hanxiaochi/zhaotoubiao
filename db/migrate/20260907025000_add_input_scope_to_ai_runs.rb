class AddInputScopeToAiRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_runs, :input_scope, :json, default: {}, null: false
  end
end

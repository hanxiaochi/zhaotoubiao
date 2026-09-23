class AddRawOutputToAiRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_runs, :raw_output, :text
  end
end

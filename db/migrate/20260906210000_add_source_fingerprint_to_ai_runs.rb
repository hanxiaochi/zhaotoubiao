class AddSourceFingerprintToAiRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_runs, :source_fingerprint, :string
  end
end

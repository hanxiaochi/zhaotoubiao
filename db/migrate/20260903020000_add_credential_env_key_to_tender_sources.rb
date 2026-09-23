class AddCredentialEnvKeyToTenderSources < ActiveRecord::Migration[8.1]
  def change
    add_column :tender_sources, :credential_env_key, :string
  end
end

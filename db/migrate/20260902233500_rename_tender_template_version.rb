class RenameTenderTemplateVersion < ActiveRecord::Migration[8.1]
  def change
    rename_column :tender_templates, :version, :revision_number
  end
end

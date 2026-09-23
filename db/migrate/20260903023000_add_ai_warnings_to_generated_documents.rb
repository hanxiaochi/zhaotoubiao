class AddAiWarningsToGeneratedDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :generated_documents, :ai_warnings, :json, default: [], null: false
  end
end

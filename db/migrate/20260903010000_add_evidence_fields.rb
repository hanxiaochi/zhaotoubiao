class AddEvidenceFields < ActiveRecord::Migration[8.1]
  def change
    add_column :claims, :analysis_data, :json, default: {}, null: false
    add_column :claim_materials, :extraction_confidence, :decimal, precision: 5, scale: 2
  end
end

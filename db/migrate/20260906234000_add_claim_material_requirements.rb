class AddClaimMaterialRequirements < ActiveRecord::Migration[8.1]
  def change
    %i[material_requirement signature_requirement seal_requirement authorization_requirement].each do |field|
      add_column :claim_materials, field, :string, null: false, default: field == :material_requirement ? "required" : "undetermined"
      add_check_constraint :claim_materials, "#{field} IN ('required', 'not_required', 'undetermined')", name: "claim_materials_#{field}_valid"
    end
    add_column :claim_materials, :requirement_note, :text
  end
end

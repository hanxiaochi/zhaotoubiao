class AddAssetSourceContext < ActiveRecord::Migration[8.1]
  def change
    add_column :assets, :source_reference, :string
    add_column :assets, :description, :text
  end
end

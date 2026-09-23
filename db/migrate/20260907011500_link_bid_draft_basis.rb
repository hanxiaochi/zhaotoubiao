class LinkBidDraftBasis < ActiveRecord::Migration[8.1]
  def change
    add_reference :generated_documents, :bid_analysis, foreign_key: true
    add_column :generated_documents, :bid_basis_snapshot, :json, null: false, default: {}
  end
end

class AddReviewNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :bid_analyses, :review_note, :text
    add_column :generated_documents, :review_note, :text
  end
end

class AddBidAnalysisReviewSections < ActiveRecord::Migration[8.1]
  def change
    %i[qualification_requirements disqualification_clauses time_nodes suggested_tasks].each do |field|
      add_column :bid_analyses, field, :json, default: [], null: false
    end
  end
end

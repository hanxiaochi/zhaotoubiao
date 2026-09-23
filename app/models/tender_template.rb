class TenderTemplate < ApplicationRecord
  include HasPublicId
  has_paper_trail

  belongs_to :created_by, class_name: "User"
  validates :name, :project_category, :tender_method, :body, presence: true
  validates :revision_number, numericality: { only_integer: true, greater_than: 0 }
end

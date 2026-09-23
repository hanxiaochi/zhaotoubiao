class AssetVersion < ApplicationRecord
  belongs_to :asset
  belongs_to :changed_by, class_name: "User"

  validates :change_reason, :snapshot, presence: true
end

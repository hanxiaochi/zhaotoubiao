class Department < ApplicationRecord
  include HasPublicId

  has_many :projects, dependent: :restrict_with_error
  has_many :users, dependent: :nullify
  validates :name, :code, presence: true
  validates :code, uniqueness: true
end

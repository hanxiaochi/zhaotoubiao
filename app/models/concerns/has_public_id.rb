module HasPublicId
  extend ActiveSupport::Concern

  included do
    before_validation :assign_public_id, on: :create
    validates :public_id, presence: true, uniqueness: true
  end

  def to_param
    public_id
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end

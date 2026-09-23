class Notification < ApplicationRecord
  include HasPublicId

  belongs_to :user
  validates :kind, :title, presence: true
  scope :unread, -> { where(read_at: nil) }

  # A unique database key, not an exists? check, arbitrates concurrent deliveries.
  def self.deliver_once!(user:, kind:, reference:, date:, **attributes)
    key = Digest::SHA256.hexdigest([ user.id, kind, reference.class.name, reference.id, date.iso8601 ].join(":"))
    transaction(requires_new: true) do
      create!(attributes.merge(user: user, kind: kind, deduplication_key: key))
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end

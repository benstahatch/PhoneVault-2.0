class SecurityEvent < ApplicationRecord
  belongs_to :user, optional: true

  validates :event_type, presence: true, length: { maximum: 50 }
  validates :ip_address, length: { maximum: 45 }, allow_nil: true
end

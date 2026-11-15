class SecurityEvent < ApplicationRecord
  DETAILS_LIMIT = 255

  belongs_to :user, optional: true
  # no foreign key, so the subject may have been deleted since; details still describe it
  belongs_to :subject, polymorphic: true, optional: true

  validates :event_type, presence: true, length: { maximum: 50 }
  validates :ip_address, length: { maximum: 45 }, allow_nil: true
  validates :details, length: { maximum: DETAILS_LIMIT }, allow_nil: true
end

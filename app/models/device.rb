class Device < ApplicationRecord
  belongs_to :user

  enum :device_type, {
    phone: "phone",
    laptop: "laptop",
    tablet: "tablet",
    desktop: "desktop",
    other: "other"
  }, validate: true

  validates :name,
    presence: true,
    length: { maximum: 100 },
    uniqueness: { scope: :user_id, case_sensitive: false }

  normalizes :name, with: ->(name) { name.strip }
end

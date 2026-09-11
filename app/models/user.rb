class User < ApplicationRecord
  has_secure_password

  has_many :devices, dependent: :destroy

  validates :username,
    presence: true,
    uniqueness: { case_sensitive: false },
    length: { minimum: 3, maximum: 50 },
    # \A and \z covers the entire string while ^ and $ match line boundaries in ruby which would allows for something like "ben\nanything"
    format: { with: /\A[a-z0-9_]+\z/i,
        message: "may only contain letters, numbers, and underscores" }

    validates :display_name, presence: true, length: { maximum: 100 }
    # allow_nil: password is nil on any update that isn't a password change
    validates :password, length: { minimum: 8 }, allow_nil: true

    normalizes :username, with: ->(name) { name.strip.downcase }
end

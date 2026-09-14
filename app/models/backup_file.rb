class BackupFile < ApplicationRecord
  belongs_to :backup_run

  validates :original_filename, presence: true
  validates :storage_path, presence: true
  validates :size_bytes, numericality: { greater_than_or_equal_to: 0 }
  validates :sha256,
    presence: true,
    length: { is: 64 },
    format: { with: /\A[0-9a-f]{64}\z/i }
end

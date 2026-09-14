class BackupRun < ApplicationRecord
  belongs_to :device
  has_many :backup_files, dependent: :restrict_with_error

  enum :status, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed"
  }, validate: true
end

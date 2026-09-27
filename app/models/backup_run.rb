class BackupRun < ApplicationRecord
  belongs_to :device
  has_many :backup_files, dependent: :restrict_with_error

  enum :status, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed"
  }, validate: true

  def start!
    update!(status: :running, started_at: Time.current)
  end

  def complete!
    update!(status: :completed, completed_at: Time.current)
  end

  def fail!
    update!(status: :failed, completed_at: Time.current)
  end
end

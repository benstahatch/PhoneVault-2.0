# Plain-language names for security events, and which ones deserve attention.
module ActivityHelper
  EVENT_LABELS = {
    "LOGIN_SUCCESS" => "Signed in",
    "LOGIN_FAILED" => "Failed sign-in attempt",
    "LOGIN_RATE_LIMITED" => "Sign-in blocked after too many attempts",
    "LOGOUT" => "Signed out",
    "ACCOUNT_CREATED" => "Account created",
    "DEVICE_REGISTERED" => "Registered a device",
    "DEVICE_RENAMED" => "Renamed a device",
    "BACKUP_SUCCESS" => "Backed up a file",
    "BACKUP_FAILED" => "Backup failed",
    "FILE_RESTORED" => "Restored a file",
    "FILE_PERMANENTLY_DELETED" => "Permanently deleted a file",
    "RESTORE_FILE_MISSING" => "Restore failed: file missing",
    "RESTORE_FILE_CORRUPTED" => "Restore failed: file did not pass its check"
  }.freeze

  # events someone should look at: a stranger guessing passwords, or storage problems
  WARNING_EVENTS = %w[LOGIN_FAILED LOGIN_RATE_LIMITED BACKUP_FAILED RESTORE_FILE_MISSING RESTORE_FILE_CORRUPTED].freeze

  def event_label(event)
    EVENT_LABELS.fetch(event.event_type) { event.event_type.humanize }
  end

  def warning_event?(event)
    WARNING_EVENTS.include?(event.event_type)
  end
end

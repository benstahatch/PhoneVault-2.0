# Server-level switch and shared date/query helpers for Trash retention.
class TrashRetention
  def self.expired_files_for(user, retention_days)
    return BackupFile.none unless User::TRASH_RETENTION_DAYS.include?(retention_days)

    BackupFile.joins(backup_run: :device)
      .where(devices: { user_id: user.id })
      .trashed
      .where("backup_files.deleted_at <= ?", retention_days.days.ago)
  end

  def self.expiration_at(deleted_at, retention_days)
    return if retention_days.nil?

    deleted_at + retention_days.days
  end

  def self.cleanup_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("PHONEVAULT_TRASH_CLEANUP_ENABLED", "false"))
  end
end

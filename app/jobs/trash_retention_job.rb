require "digest"

class TrashRetentionJob < ApplicationJob
  queue_as :background

  LOCK_NAME_PREFIX = "phonevault_trash_retention_cleanup".freeze

  # Pass dry_run: true to report expired files without changing storage or rows.
  def perform(dry_run: false)
    retention_days = TrashRetention.retention_days
    cutoff = retention_days.days.ago

    if dry_run
      return expired_files(cutoff).map { |file| preview(file, retention_days) }
    end

    unless TrashRetention.cleanup_enabled?
      Rails.logger.info("Trash retention cleanup is disabled; no files were changed.")
      return []
    end

    with_cleanup_lock do
      expired_files(cutoff).filter_map { |file| delete_if_still_expired(file.id, cutoff, retention_days) }
    end
  end

  private

  def expired_files(cutoff)
    BackupFile.trashed
      .joins(backup_run: { device: :user })
      .includes(backup_run: { device: :user })
      .where("backup_files.deleted_at <= ?", cutoff)
      .order(:id)
  end

  def preview(file, retention_days)
    storage = backup_storage_for(file.backup_run)
    verify_before_delete(storage, file)
    result(file, "would_delete", retention_days)
  rescue BackupStorage::Error, BackupDirectory::Error, SystemCallError => error
    Rails.logger.warn("Trash retention dry run skipped backup_file_id=#{file.id}: #{error.message}")
    result(file, "would_fail", retention_days, error.message)
  end

  def delete_if_still_expired(file_id, cutoff, retention_days)
    BackupFile.transaction do
      file = BackupFile.joins(backup_run: { device: :user })
        .where(id: file_id)
        .where.not(deleted_at: nil)
        .where("backup_files.deleted_at <= ?", cutoff)
        .lock
        .first
      next unless file

      storage = backup_storage_for(file.backup_run)
      storage.permanently_delete(file)

      owner = file.backup_run.device.user
      event = SecurityEvent.new(
        user: owner,
        subject: file,
        event_type: "FILE_PERMANENTLY_DELETED",
        details: "Auto-deleted #{file.original_filename.truncate(180)} after #{retention_days}-day Trash retention."
      )
      file.destroy!
      event.save!

      Rails.logger.info("Trash retention permanently deleted backup_file_id=#{file_id} owner_id=#{owner.id}")
      result(file, "deleted", retention_days)
    end
  rescue StandardError => error
    Rails.logger.error("Trash retention failed for backup_file_id=#{file_id}; record retained when possible: #{error.class}: #{error.message}")
    { backup_file_id: file_id, status: "failed", error: error.message }
  end

  def verify_before_delete(storage, file)
    case storage.verify(file)
    when :ok
      true
    when :missing
      raise BackupStorage::MissingFile, "backup file #{file.id} is missing from storage"
    when :corrupted
      raise BackupStorage::CorruptedFile, "backup file #{file.id} failed integrity verification"
    end
  end

  def backup_storage_for(run)
    BackupStorage.for_run(run)
  end

  def result(file, status, retention_days, error = nil)
    {
      backup_file_id: file.id,
      filename: file.original_filename,
      device: file.backup_run.device.name,
      owner: file.backup_run.device.user.username,
      size_bytes: file.size_bytes,
      deleted_at: file.deleted_at,
      retention_days: retention_days,
      status: status,
      error: error
    }
  end

  def with_cleanup_lock
    BackupFile.connection_pool.with_connection do |connection|
      lock_name = cleanup_lock_name(connection)
      acquired = connection.select_value("SELECT GET_LOCK(#{connection.quote(lock_name)}, 0)").to_i == 1
      unless acquired
        Rails.logger.info("Trash retention cleanup skipped because another cleanup is running.")
        next []
      end

      begin
        yield
      ensure
        connection.select_value("SELECT RELEASE_LOCK(#{connection.quote(lock_name)})")
      end
    end
  end

  def cleanup_lock_name(connection)
    database_name = connection.select_value("SELECT DATABASE()")
    cleanup_lock_name_for_database(database_name)
  end

  def cleanup_lock_name_for_database(database_name)
    "#{LOCK_NAME_PREFIX}_#{Digest::SHA256.hexdigest(database_name)[0, 24]}"
  end
end

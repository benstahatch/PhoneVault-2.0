class TrashController < ApplicationController
  def index
    @backup_files = current_user.backup_files.trashed
      .includes(backup_run: :device)
      .order(deleted_at: :desc, id: :desc)
      .load
    @retention_days = current_user.trash_retention_days
    @automatic_cleanup_enabled = TrashRetention.cleanup_enabled?
  end

  def restore
    file = current_user.backup_files.trashed.find(params[:id])
    file.update!(deleted_at: nil)
    record_security_event("FILE_RECOVERED_FROM_TRASH", current_user)

    redirect_to trashed_files_path,
      notice: "#{file.original_filename} restored to backup history.",
      status: :see_other
  end

  def destroy
    file = current_user.backup_files.trashed.find(params[:id])
    storage = BackupStorage.for_run(file.backup_run)
    storage.permanently_delete(file)
    filename = file.original_filename

    BackupFile.transaction do
      file.destroy!
      record_security_event("FILE_PERMANENTLY_DELETED", current_user)
    end

    redirect_to trashed_files_path,
      notice: "#{filename} was permanently deleted.",
      status: :see_other
  rescue BackupStorage::MissingFile
    redirect_to trashed_files_path, alert: "Backup file is missing from storage. The Trash record was kept."
  rescue BackupStorage::CorruptedFile
    redirect_to trashed_files_path, alert: "Backup file failed integrity verification. The Trash record was kept."
  rescue BackupStorage::Error, BackupDirectory::Error => error
    redirect_to trashed_files_path, alert: "Backup file could not be deleted. The Trash record was kept. #{error.message}"
  end
end

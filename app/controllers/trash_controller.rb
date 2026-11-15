class TrashController < ApplicationController
  def index
    @backup_files = owned_trashed_files
      .includes(backup_run: :device)
      .order(deleted_at: :desc, id: :desc)
      .load
  end

  def restore
    file = owned_trashed_files.find(params[:id])
    file.update!(deleted_at: nil)
    record_security_event("FILE_RECOVERED_FROM_TRASH", current_user)

    redirect_to trash_path,
      notice: "#{file.original_filename} restored to backup history.",
      status: :see_other
  end

  private

  def owned_trashed_files
    BackupFile.joins(backup_run: :device)
      .where(devices: { user_id: current_user.id })
      .trashed
  end
end

class BackupFilesController < ApplicationController
  include DeviceScoped
  before_action :set_backup_file

  rescue_from BackupDirectory::Error do |error|
    redirect_to device_backup_runs_path(@device), alert: error.message
  end

  rescue_from BackupStorage::MissingFile, with: :missing_file
  rescue_from BackupStorage::CorruptedFile, with: :corrupted_file

  def restore
    # raises MissingFile or CorruptedFile (handled below) unless the size and sha-256 match
    path = BackupStorage.for_run(@backup_run).restore(@backup_file)
    record_security_event("FILE_RESTORED", current_user, subject: @backup_file, details: @backup_file.summary)

    # the filename came from the user, so sanitize it before it goes into a response header
    send_file path.to_s, filename: ActiveStorage::Filename.new(@backup_file.original_filename).sanitized,
      disposition: "attachment"
  end

  def destroy
    @backup_file.update!(deleted_at: Time.current)
    record_security_event("FILE_TRASHED", current_user, subject: @backup_file, details: @backup_file.summary)

    redirect_to device_backup_runs_path(@device),
      notice: "#{@backup_file.original_filename} moved to Trash.",
      status: :see_other
  end

  # shows an image thumbnail in the backup history; only real images are served
  def preview
    content_type = BackupPreview.new.image_type(@backup_file)
    return head :not_found unless content_type

    # nothing in this response may run scripts, even if a browser misreads it
    response.headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'"
    response.headers["Cache-Control"] = "private, max-age=3600"

    # path_for keeps the path inside the backup folder, just like restore
    path = BackupStorage.for_run(@backup_run).path_for(@backup_file)

    send_file path.to_s, type: content_type, disposition: "inline"
  end

  private

  # each lookup is scoped to the one before it: user → device → run → active file
  def set_backup_file
    @backup_run = @device.backup_runs.find(params[:backup_run_id])
    @backup_file = @backup_run.backup_files.active.find(params[:id])
  end

  def missing_file
    # return to backup history if the stored file no longer exists
    record_security_event("RESTORE_FILE_MISSING", current_user, subject: @backup_file, details: @backup_file.summary)
    redirect_to device_backup_runs_path(@device),
      alert: "Backup file is missing from storage."
  end

  def corrupted_file
    # return to backup history if the stored file fails sha-256 verification
    record_security_event("RESTORE_FILE_CORRUPTED", current_user, subject: @backup_file, details: @backup_file.summary)
    redirect_to device_backup_runs_path(@device),
      alert: "Backup file failed integrity verification."
  end
end

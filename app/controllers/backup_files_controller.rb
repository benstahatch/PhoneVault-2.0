class BackupFilesController < ApplicationController
  before_action :set_device
  before_action :set_backup_run
  before_action :set_backup_file

  rescue_from BackupStorage::MissingFile, with: :missing_file
  rescue_from BackupStorage::CorruptedFile, with: :corrupted_file

def restore
  # verify the file and return its safe path on disk
  path = BackupStorage.new.restore(@backup_file)

  # only reached when the file exists and its sha-256 matches
  record_security_event("FILE_RESTORED", current_user)

  # sanitize the user-provided filename before sending it to the browser
  safe_filename = ActiveStorage::Filename
    .new(@backup_file.original_filename)
    .sanitized

  # send the verified file back using the sanitized filename
  send_file path.to_s,
    filename: safe_filename,
    disposition: "attachment"
end

  # shows an image thumbnail in the backup history; only real images are served
  def preview
    content_type = BackupPreview.new.image_type(@backup_file)
    return head :not_found unless content_type

    # nothing in this response may run scripts, even if a browser misreads it
    response.headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'"
    response.headers["Cache-Control"] = "private, max-age=3600"

    # path_for keeps the path inside the backup folder, just like restore
    path = BackupStorage.new.path_for(@backup_file)

    send_file path.to_s, type: content_type, disposition: "inline"
  end

  private

  def set_device
    # only find devices owned by the logged-in user
    @device = current_user.devices.find(params[:device_id])
  end

  def set_backup_run
    # only find backup runs belonging to this device
    @backup_run = @device.backup_runs.find(params[:backup_run_id])
  end

  def set_backup_file
    # only find files belonging to this backup run
    @backup_file = @backup_run.backup_files.find(params[:id])
  end

  def missing_file
    # return to backup history if the stored file no longer exists
    record_security_event("RESTORE_FILE_MISSING", current_user)
    redirect_to device_backup_runs_path(@device),
      alert: "Backup file is missing from storage."
  end

  def corrupted_file
    # return to backup history if the stored file fails sha-256 verification
    record_security_event("RESTORE_FILE_CORRUPTED", current_user)
    redirect_to device_backup_runs_path(@device),
      alert: "Backup file failed integrity verification."
  end
end

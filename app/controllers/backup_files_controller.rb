class BackupFilesController < ApplicationController
  before_action :set_device
  before_action :set_backup_run
  before_action :set_backup_file

  rescue_from BackupStorage::MissingFile, with: :missing_file
  rescue_from BackupStorage::CorruptedFile, with: :corrupted_file

  def restore
    # verify the file and return its safe path on disk
    path = BackupStorage.new.restore(@backup_file)

    # send the verified file back using its original filename
    send_file path.to_s,
      filename: @backup_file.original_filename,
      disposition: "attachment"
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
    redirect_to device_backup_runs_path(@device),
      alert: "Backup file is missing from storage."
  end

  def corrupted_file
    # return to backup history if the stored file fails sha-256 verification
    redirect_to device_backup_runs_path(@device),
      alert: "Backup file failed integrity verification."
  end
end

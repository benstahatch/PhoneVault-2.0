class BackupsController < ApplicationController
  before_action :set_device

  def new
  end

  def create
    uploaded_file = params[:file]

    backup_run = @device.backup_runs.create!(status: :pending)
    backup_run.start!

    BackupStorage.new.store(
      uploaded_file,
      backup_run: backup_run,
      original_filename: uploaded_file.original_filename
    )

    backup_run.complete!

    redirect_to devices_path, notice: "Backup completed successfully."
  end

  private

  def set_device
    @device = current_user.devices.find(params[:device_id])
  end
end

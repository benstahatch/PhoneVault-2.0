class BackupRunsController < ApplicationController
  before_action :set_device

  def index
    @backup_runs = @device.backup_runs.order(created_at: :desc)
  end

  def new
    @backup_run = @device.backup_runs.new
  end

  def create
    uploaded_file = params.expect(backup_run: [ :file ])[:file]
    if uploaded_file.blank?
      @backup_run = @device.backup_runs.new
      @backup_run.errors.add(:base, "Choose a file to upload")
      return render :new, status: :unprocessable_entity
    end

    @backup_run = @device.backup_runs.create!(status: :pending)
    @backup_run.start!

    begin
      BackupStorage.new.store(uploaded_file, backup_run: @backup_run, original_filename: uploaded_file.original_filename)
      @backup_run.complete!
    rescue StandardError
      # mark the run failed before logging, so the status is saved even if logging fails
      @backup_run.fail!
      record_security_event("BACKUP_FAILED", current_user)
      return redirect_to device_backup_runs_path(@device), alert: "Backup failed to store the file."
    end

    # recorded outside begin/rescue so a logging error can't mark a stored backup as failed
    record_security_event("BACKUP_SUCCESS", current_user)
    redirect_to device_backup_runs_path(@device), notice: "Backup completed."
  end

  private

  def set_device
    @device = current_user.devices.find(params[:device_id])
  end
end

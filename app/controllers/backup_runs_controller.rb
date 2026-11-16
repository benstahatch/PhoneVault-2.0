class BackupRunsController < ApplicationController
  include DeviceScoped

  def index
    runs = @device.backup_runs.includes(:active_backup_files).order(created_at: :desc, id: :desc).to_a
    @backup_runs = runs.reject { |run| run.completed? && run.active_backup_files.empty? }
    @preview = BackupPreview.new
  end

  def new
    @backup_run = @device.backup_runs.new
    @save_path = BackupDirectory.resolve_or_default!(params[:save_path], current_user).to_s
  rescue BackupDirectory::Error => error
    @backup_run.errors.add(:base, error.message)
  end

  def create
    attributes = params.expect(backup_run: [ :file, :save_path ])
    uploaded_file = attributes[:file]
    @save_path = attributes[:save_path]
    return render_new_with_error("Choose a file to upload") if uploaded_file.blank?

    destination = begin
      BackupDirectory.test_write!(@save_path)
    rescue BackupDirectory::Error => error
      return render_new_with_error(error.message)
    end

    @backup_run = @device.backup_runs.create!(status: :pending, storage_root: destination.to_s)
    @backup_run.start!

    begin
      storage = BackupStorage.for_run(@backup_run)
      backup_file = storage.store(uploaded_file, backup_run: @backup_run, original_filename: uploaded_file.original_filename)
      @backup_run.complete!
    rescue StandardError => error
      # mark the run failed before logging, so the status is saved even if logging fails
      @backup_run.fail!
      too_large = error.is_a?(BackupStorage::TooLarge)
      record_security_event("BACKUP_FAILED", current_user, subject: @backup_run,
        details: "#{uploaded_file.original_filename} to #{@device.name}#{' (over the size limit)' if too_large}")

      alert = too_large ? "File is larger than the #{helpers.number_to_human_size(storage.max_bytes)} upload limit." : "Backup failed to store the file."
      return redirect_to device_backup_runs_path(@device), alert: alert
    end

    # recorded outside begin/rescue so a logging error can't mark a stored backup as failed
    record_security_event("BACKUP_SUCCESS", current_user, subject: backup_file,
      details: "#{backup_file.original_filename} to #{@device.name}")
    redirect_to device_backup_runs_path(@device), notice: "File uploaded successfully. Backup completed."
  end

  private

  def render_new_with_error(message)
    @backup_run = @device.backup_runs.new
    @backup_run.errors.add(:base, message)
    render :new, status: :unprocessable_entity
  end
end

class BackupLocationsController < ApplicationController
  before_action :set_device
  rescue_from BackupDirectory::Error, with: :directory_error

  def directories
    browser = BackupDirectory.for_user(current_user)
    @root = browser.root
    @path = browser.resolve!(params[:path].presence || @root.to_s)
    @directories = browser.children(@path)
    respond_to do |format|
      format.html
      format.json do
        render json: {
          path: @path.to_s,
          parent: @path == @root ? nil : @path.parent.to_s,
          directories: @directories.map { |directory| { name: directory.basename.to_s, path: directory.to_s } }
        }
      end
    end
  end

  def validate_path
    browser = BackupDirectory.for_user(current_user)
    path = browser.test_write!(params[:path])
    render json: { message: "Directory exists and is writable.", path: path.to_s }
  end

  private

  def set_device
    @device = current_user.devices.find(params[:device_id])
  end

  def directory_error(error)
    if action_name == "validate_path" || request.format.json?
      render json: { error: error.message }, status: :unprocessable_entity
    else
      redirect_to new_device_backup_run_path(@device), alert: error.message
    end
  end
end

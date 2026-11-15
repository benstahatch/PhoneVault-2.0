class BackupLocationsController < ApplicationController
  include DeviceScoped
  rescue_from BackupDirectory::Error, with: :directory_error

  def directories
    @path = BackupDirectory.resolve_or_default!(params[:path], current_user)
    @directories = BackupDirectory.children(@path)
    respond_to do |format|
      format.html
      format.json do
        render json: {
          path: @path.to_s,
          parent: (@path.parent.to_s unless @path.root?),
          directories: @directories.map { |directory| { name: directory.basename.to_s, path: directory.to_s } }
        }
      end
    end
  end

  def validate_path
    path = BackupDirectory.test_write!(params[:path])
    render json: { message: "Directory exists and is writable.", path: path.to_s }
  end

  private

  def directory_error(error)
    if action_name == "validate_path" || request.format.json?
      render json: { error: error.message }, status: :unprocessable_entity
    else
      redirect_to new_device_backup_run_path(@device), alert: error.message
    end
  end
end

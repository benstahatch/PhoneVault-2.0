class DashboardController < ApplicationController
  def show
    @user = current_user
    @device_count = @user.devices.count
    @file_count = @user.backup_files.count
    @stored_bytes = @user.backup_files.sum(:size_bytes)
    @latest_backup = @user.backup_runs.completed.where.not(completed_at: nil)
      .includes(:device).order(completed_at: :desc, id: :desc).first
    @recent_runs = @user.backup_runs.includes(:device).order(created_at: :desc, id: :desc).limit(5).load
  end
end

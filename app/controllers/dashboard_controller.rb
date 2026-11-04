class DashboardController < ApplicationController
  def show
    @user = current_user
    @device_count = @user.devices.count
    # Follow belongs_to associations so each file contributes exactly once.
    runs = BackupRun.joins(:device).where(devices: { user_id: @user.id })
    files = BackupFile.joins(backup_run: :device).where(devices: { user_id: @user.id })
    @file_count = files.count
    @stored_bytes = files.sum(:size_bytes)
    @latest_backup = runs.completed.where.not(completed_at: nil)
      .includes(:device).order(completed_at: :desc, id: :desc).first
    @recent_runs = runs.includes(:device).order(created_at: :desc, id: :desc).limit(5).load
  end
end

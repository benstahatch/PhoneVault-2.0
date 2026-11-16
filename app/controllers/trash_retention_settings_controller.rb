class TrashRetentionSettingsController < ApplicationController
  def edit
    @retention_days = current_user.trash_retention_days
    @automatic_cleanup_enabled = TrashRetention.cleanup_enabled?
  end

  # Shows the files a new period would make eligible and issues a one-time confirmation token.
  # Never, or any period while server cleanup is off, deletes nothing, so it saves right away.
  def confirm
    @retention_days = requested_retention_days
    return save_retention(@retention_days) if @retention_days.nil? || !TrashRetention.cleanup_enabled?

    @eligible_files = TrashRetention.expired_files_for(current_user, @retention_days)
      .includes(backup_run: :device)
      .order(deleted_at: :asc, id: :asc)
      .load
    @confirmation_token = SecureRandom.hex(32)
    session[:trash_retention_confirmation] = {
      user_id: current_user.id,
      days: @retention_days,
      token: @confirmation_token,
      expires_at: 15.minutes.from_now.to_i
    }
  rescue ArgumentError
    redirect_to edit_trash_retention_settings_path, alert: "Choose Never, 30, 60, or 90 days."
  end

  def update
    retention_days = requested_retention_days
    confirmation = session.delete(:trash_retention_confirmation)
    if retention_days && !valid_confirmation?(confirmation, retention_days)
      return redirect_to edit_trash_retention_settings_path,
        alert: "Review the retention warning and confirm the change before saving."
    end

    save_retention(retention_days)
  rescue ArgumentError, ActiveRecord::RecordInvalid
    redirect_to edit_trash_retention_settings_path, alert: "Choose Never, 30, 60, or 90 days."
  end

  private

  def save_retention(days)
    session.delete(:trash_retention_confirmation)
    current_user.update!(trash_retention_days: days)
    redirect_to trashed_files_path, notice: days ? "Trash retention is set to #{days} days." :
      "Trash retention is set to Never. Files stay until you restore or delete them."
  end

  # nil for Never; raises ArgumentError for anything other than a supported number of days
  def requested_retention_days
    value = params[:trash_retention_days]
    return if value.blank?

    days = Integer(value.to_s, 10)
    User::TRASH_RETENTION_DAYS.include?(days) ? days : raise(ArgumentError)
  end

  # the checkbox is ticked, and the token matches the one confirm issued to this user, for these days, within 15 minutes
  def valid_confirmation?(confirmation, retention_days)
    params[:confirm_retention] == "1" && confirmation.is_a?(Hash) &&
      confirmation["user_id"] == current_user.id && confirmation["days"] == retention_days &&
      confirmation["expires_at"].to_i >= Time.current.to_i &&
      ActiveSupport::SecurityUtils.secure_compare(params[:confirmation_token].to_s, confirmation["token"].to_s)
  end
end

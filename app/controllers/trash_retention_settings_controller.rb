class TrashRetentionSettingsController < ApplicationController
  def edit
    load_settings
  end

  def confirm
    @retention_days = requested_retention_days
    if @retention_days.nil?
      current_user.update!(trash_retention_days: nil)
      session.delete(:trash_retention_confirmation)
      return redirect_to trashed_files_path, notice: "Trash retention is set to Never. Files stay until you restore or delete them."
    end

    unless TrashRetention.cleanup_enabled?
      current_user.update!(trash_retention_days: @retention_days)
      session.delete(:trash_retention_confirmation)
      return redirect_to trashed_files_path, notice: "Trash retention is set to #{@retention_days} days."
    end

    load_settings
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
    if retention_days.nil?
      current_user.update!(trash_retention_days: nil)
      session.delete(:trash_retention_confirmation)
      return redirect_to trashed_files_path, notice: "Trash retention is set to Never. Files stay until you restore or delete them."
    end

    confirmation = session.delete(:trash_retention_confirmation)
    unless valid_confirmation?(confirmation, retention_days)
      return redirect_to edit_trash_retention_settings_path,
        alert: "Review the retention warning and confirm the change before saving."
    end

    current_user.update!(trash_retention_days: retention_days)
    redirect_to trashed_files_path, notice: "Trash retention is set to #{retention_days} days."
  rescue ArgumentError, ActiveRecord::RecordInvalid
    redirect_to edit_trash_retention_settings_path, alert: "Choose Never, 30, 60, or 90 days."
  end

  private

  def load_settings
    @retention_days = current_user.trash_retention_days unless defined?(@retention_days)
    @automatic_cleanup_enabled = TrashRetention.cleanup_enabled?
  end

  def requested_retention_days
    value = params[:trash_retention_days]
    return if value.blank?

    days = Integer(value, 10)
    raise ArgumentError unless User::TRASH_RETENTION_DAYS.include?(days)

    days
  rescue TypeError
    raise ArgumentError
  end

  def valid_confirmation?(confirmation, retention_days)
    return false unless params[:confirm_retention] == "1"
    return false unless confirmation.is_a?(Hash)
    return false unless confirmation["user_id"] == current_user.id && confirmation["days"] == retention_days
    return false unless confirmation["expires_at"].to_i >= Time.current.to_i

    submitted_token = params[:confirmation_token].to_s
    stored_token = confirmation["token"].to_s
    submitted_token.bytesize == stored_token.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(submitted_token, stored_token)
  end
end

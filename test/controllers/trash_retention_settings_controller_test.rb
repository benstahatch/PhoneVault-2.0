require "test_helper"

class TrashRetentionSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    @previous_cleanup_enabled = ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"]
    @root = Dir.mktmpdir("phonevault_retention_settings")
    ENV["PHONEVAULT_BACKUP_ROOT"] = @root
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "false"
    @user = users(:alice)
    @user.update!(trash_retention_days: nil)
    @device = devices(:alice_phone)
    @run = @device.backup_runs.create!(status: :completed, storage_root: @root)
    @file = upload(@run, "old-photo.jpg", "image bytes")
    @file.update!(deleted_at: 35.days.ago)
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    @previous_cleanup_enabled ? ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = @previous_cleanup_enabled : ENV.delete("PHONEVAULT_TRASH_CLEANUP_ENABLED")
    FileUtils.remove_entry(@root)
  end

  test "settings require login" do
    get trash_retention_settings_path
    assert_redirected_to login_path
  end

  test "settings offer Never and the supported periods, with Never selected initially" do
    sign_in_as @user

    get trash_retention_settings_path

    assert_response :success
    assert_select "h1", text: "Retention Settings"
    assert_select "select[name='trash_retention_days'] option[selected]", text: "Never (keep files until manually deleted)"
    assert_select "option[value='30']", text: "30 days (recommended)"
    assert_select "option[value='60']", text: "60 days"
    assert_select "option[value='90']", text: "90 days"
    assert_match "Server-level automatic cleanup is disabled", response.body
  end

  test "confirmation lists the current user's files already eligible from deleted_at" do
    other_run = devices(:bob_phone).backup_runs.create!(status: :completed, storage_root: @root)
    other_file = upload(other_run, "bob-private.jpg", "private bytes")
    other_file.update!(deleted_at: 90.days.ago)
    sign_in_as @user

    post confirm_trash_retention_settings_path, params: { trash_retention_days: "30" }

    assert_response :success
    assert_select "h1", text: "Confirm Retention Settings"
    assert_match "1 file has been in Trash", response.body
    assert_match "old-photo.jpg", response.body
    assert_no_match "bob-private.jpg", response.body
    assert_match "disabled", response.body
    assert_select "input[name='confirm_retention'][required]"
    assert_select "td time[datetime=?]", (@file.deleted_at + 30.days).iso8601
    assert_not_nil other_file.reload.deleted_at
  end

  test "saving a retention period requires the confirmation flow and checkbox" do
    sign_in_as @user

    patch update_trash_retention_settings_path, params: { trash_retention_days: "30" }

    assert_redirected_to trash_retention_settings_path
    assert_equal "Review the retention warning and confirm the change before saving.", flash[:alert]
    assert_nil @user.reload.trash_retention_days
  end

  test "confirmed period persists but clearly reports when server cleanup is disabled" do
    sign_in_as @user
    post confirm_trash_retention_settings_path, params: { trash_retention_days: "30" }
    token = css_select("input[name='confirmation_token']").first["value"]

    patch update_trash_retention_settings_path, params: {
      trash_retention_days: "30",
      confirmation_token: token,
      confirm_retention: "1"
    }

    assert_redirected_to trash_path
    assert_equal 30, @user.reload.trash_retention_days
    follow_redirect!
    assert_match "Your 30-day preference is saved, but server-level automatic cleanup is disabled", response.body
    assert_match "files will not be automatically deleted", response.body
  end

  test "confirmed period persists when server cleanup is enabled" do
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    sign_in_as @user
    post confirm_trash_retention_settings_path, params: { trash_retention_days: "60" }
    token = css_select("input[name='confirmation_token']").first["value"]

    patch update_trash_retention_settings_path, params: {
      trash_retention_days: "60",
      confirmation_token: token,
      confirm_retention: "1"
    }

    assert_redirected_to trash_path
    assert_equal 60, @user.reload.trash_retention_days
    assert_match "scheduled cleanup", flash[:notice]
  end

  test "Never disables the user preference without deletion confirmation" do
    @user.update!(trash_retention_days: 90)
    sign_in_as @user

    post confirm_trash_retention_settings_path, params: { trash_retention_days: "" }

    assert_redirected_to trash_path
    assert_nil @user.reload.trash_retention_days
    assert_equal "Trash retention is set to Never. Files stay until you restore or delete them.", flash[:notice]
    assert File.file?(BackupStorage.for_run(@run).path_for(@file))
  end

  test "unsupported periods are rejected" do
    sign_in_as @user

    post confirm_trash_retention_settings_path, params: { trash_retention_days: "7" }

    assert_redirected_to trash_retention_settings_path
    assert_equal "Choose Never, 30, 60, or 90 days.", flash[:alert]
    assert_nil @user.reload.trash_retention_days
  end

  private

  def upload(run, filename, contents)
    BackupStorage.for_run(run).store(StringIO.new(contents), backup_run: run, original_filename: filename)
  end

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

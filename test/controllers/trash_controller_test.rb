require "test_helper"

class TrashControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    @root = Dir.mktmpdir("phonevault_trash_page")
    ENV["PHONEVAULT_BACKUP_ROOT"] = @root
    @device = devices(:alice_phone)
    @run = @device.backup_runs.create!(status: :completed, storage_root: @root)
    @file = upload(@run, "family-photo.jpg", "image bytes")
    @file.update!(deleted_at: 2.hours.ago)
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    FileUtils.remove_entry(@root)
  end

  test "trash requires login" do
    get trash_path
    assert_redirected_to login_path
  end

  test "trash lists only the current user's deleted file details" do
    create_other_user_trashed_file
    sign_in_as users(:alice)

    get trash_path

    assert_response :success
    assert_select "h1", text: "Trash"
    assert_select "tbody tr", count: 1
    assert_select "tbody tr td:nth-child(1)", text: "family-photo.jpg"
    assert_select "tbody tr td:nth-child(2)", text: @device.name
    assert_select "tbody tr td:nth-child(3)", text: "11 Bytes"
    assert_select "time[datetime=?]", @file.deleted_at.iso8601
    assert_select "form[action=?][data-turbo-confirm=?]",
      restore_trash_path(@file), "Restore family-photo.jpg to backup history?"
    assert_select "form[action=?][data-turbo-confirm=?]",
      permanently_delete_trash_path(@file),
      "Permanently delete family-photo.jpg from PhoneVault storage? This cannot be undone."
    assert_no_match "bob-secret.txt", response.body
  end

  test "trash page explains when it is empty" do
    sign_in_as users(:alice)
    @file.update!(deleted_at: nil)

    get trash_path

    assert_response :success
    assert_match "Trash is empty.", response.body
  end

  test "restore from trash clears only deleted_at and preserves bytes, hash, path, and metadata" do
    sign_in_as users(:alice)
    original_path = BackupStorage.for_run(@run).path_for(@file)
    original_hash = @file.sha256
    original_path_value = @file.storage_path
    original_size = @file.size_bytes
    original_name = @file.original_filename
    original_deleted_at = @file.deleted_at

    assert_no_difference "BackupFile.count" do
      patch restore_trash_path(@file)
    end

    assert_redirected_to trash_path
    assert_equal "family-photo.jpg restored to backup history.", flash[:notice]
    @file.reload
    assert_nil @file.deleted_at
    assert_equal original_hash, @file.sha256
    assert_equal original_path_value, @file.storage_path
    assert_equal original_size, @file.size_bytes
    assert_equal original_name, @file.original_filename
    assert_not_nil original_deleted_at
    assert_equal "image bytes", File.binread(original_path)
    assert_equal :ok, BackupStorage.for_run(@run).verify(@file)
    assert_equal "FILE_RECOVERED_FROM_TRASH", SecurityEvent.order(:id).last.event_type
  end

  test "users cannot view or restore another user's trashed files" do
    file = create_other_user_trashed_file
    sign_in_as users(:alice)

    assert_no_difference "SecurityEvent.count" do
      patch restore_trash_path(file)
    end
    assert_response :not_found
    assert_not_nil file.reload.deleted_at
    get trash_path
    assert_response :success
    assert_no_match "bob-secret.txt", response.body
  end

  test "restore requires login" do
    file = create_other_user_trashed_file

    patch restore_trash_path(file)

    assert_redirected_to login_path
    assert_not_nil file.reload.deleted_at
  end

  test "permanent deletion removes only the tracked file and record, then rejects repeats" do
    sign_in_as users(:alice)
    second_file = upload(@run, "keep-this.txt", "other bytes")
    second_file.update!(deleted_at: Time.current)
    stored_path = BackupStorage.for_run(@run).path_for(@file)

    assert_difference("BackupFile.count", -1) do
      assert_difference("SecurityEvent.count", 1) do
        delete permanently_delete_trash_path(@file)
      end
    end

    assert_redirected_to trash_path
    assert_equal "family-photo.jpg was permanently deleted.", flash[:notice]
    assert_not File.exist?(stored_path)
    assert_equal "other bytes", File.binread(BackupStorage.for_run(@run).path_for(second_file))
    assert_equal "FILE_PERMANENTLY_DELETED", SecurityEvent.order(:id).last.event_type

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      delete permanently_delete_trash_path(@file)
    end
    assert_response :not_found
  end

  test "permanent deletion cannot access another user's trashed file" do
    file = create_other_user_trashed_file
    stored_path = BackupStorage.for_run(file.backup_run).path_for(file)
    sign_in_as users(:alice)

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      delete permanently_delete_trash_path(file)
    end

    assert_response :not_found
    assert_not_nil file.reload.deleted_at
    assert File.file?(stored_path)
  end

  test "permanent deletion rejects a traversal path and preserves its record" do
    sign_in_as users(:alice)
    sentinel = File.join(File.dirname(@root), "phonevault-trash-sentinel-#{SecureRandom.hex(6)}")
    File.binwrite(sentinel, "leave this alone")
    @file.update_column(:storage_path, "../../#{File.basename(sentinel)}")

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      delete permanently_delete_trash_path(@file)
    end

    assert_redirected_to trash_path
    assert_match "record was kept", flash[:alert]
    assert @file.reload.deleted_at.present?
    assert_equal "leave this alone", File.binread(sentinel)
  ensure
    File.delete(sentinel) if sentinel && File.exist?(sentinel)
  end

  test "permanent deletion keeps the record when the stored file is missing" do
    sign_in_as users(:alice)
    File.delete(BackupStorage.for_run(@run).path_for(@file))

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      delete permanently_delete_trash_path(@file)
    end

    assert_redirected_to trash_path
    assert_match "missing from storage", flash[:alert]
    assert @file.reload.deleted_at.present?
  end

  test "permanent deletion keeps the record when filesystem unlink fails" do
    sign_in_as users(:alice)
    original_unlink = File.method(:unlink)

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      File.define_singleton_method(:unlink) { |path| raise Errno::EACCES, path.to_s }
      begin
        delete permanently_delete_trash_path(@file)
      ensure
        File.define_singleton_method(:unlink, original_unlink)
      end
    end

    assert_redirected_to trash_path
    assert_match "could not be deleted", flash[:alert]
    assert_match "record was kept", flash[:alert]
    assert @file.reload.deleted_at.present?
    assert File.file?(BackupStorage.for_run(@run).path_for(@file))
  end

  private

  def upload(run, filename, contents)
    BackupStorage.for_run(run).store(StringIO.new(contents),
      backup_run: run, original_filename: filename)
  end

  def create_other_user_trashed_file
    run = devices(:bob_phone).backup_runs.create!(status: :completed, storage_root: @root)
    file = upload(run, "bob-secret.txt", "secret")
    file.update!(deleted_at: Time.current)
    file
  end

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

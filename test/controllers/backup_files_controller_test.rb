require "test_helper"

class BackupFilesControllerTest < ActionDispatch::IntegrationTest
  test "restore requires login" do
    device = devices(:alice_phone)

    get restore_device_backup_run_backup_file_path(device, 1, 1)

    assert_redirected_to login_path
  end

  test "restore cannot access another user's backup file" do
    # log in as alice
    sign_in_as users(:alice)

    # create a backup file that belongs to bob
    device = devices(:bob_phone)
    run = device.backup_runs.create!(status: :completed)

    file = run.backup_files.create!(
      original_filename: "secret.txt",
      storage_path: "fake/path",
      size_bytes: 10,
      sha256: "a" * 64
    )

    # alice should not be able to restore bob's file
    get restore_device_backup_run_backup_file_path(device, run, file)

    assert_response :not_found
  end

  test "restore downloads a verified backup file" do
    # log in as alice
    sign_in_as users(:alice)

    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed)
    uploaded_file = fixture_file_upload("sample_backup.txt", "text/plain")

    # use temporary storage so the test does not touch real backup files
    Dir.mktmpdir("phonevault_restore") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root

      begin
        # store the file using the real phonevault storage service
        backup_file = BackupStorage.new.store(
          uploaded_file,
          backup_run: run,
          original_filename: uploaded_file.original_filename
        )

        # request the restore route
        get restore_device_backup_run_backup_file_path(
          device,
          run,
          backup_file
        )

        assert_response :success

        # prove the downloaded bytes have the same sha-256
        assert_equal backup_file.sha256,
          Digest::SHA256.hexdigest(response.body)

        # make sure rails sends it as a download
        assert_includes response.headers["Content-Disposition"], "attachment"
        assert_includes response.headers["Content-Disposition"], "sample_backup.txt"

        event = SecurityEvent.order(:id).last
        assert_equal "FILE_RESTORED", event.event_type
        assert_equal users(:alice), event.user
      ensure
        if previous_root
          ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
        else
          ENV.delete("PHONEVAULT_BACKUP_ROOT")
        end
      end
    end
  end

  test "restore redirects when the stored file is missing" do
    # log in as alice
    sign_in_as users(:alice)

    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed)
    uploaded_file = fixture_file_upload("sample_backup.txt", "text/plain")

    # use temporary storage so the test does not touch real backup files
    Dir.mktmpdir("phonevault_missing_restore") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root

      begin
        # store a real backup file first
        backup_file = BackupStorage.new.store(
          uploaded_file,
          backup_run: run,
          original_filename: uploaded_file.original_filename
        )

        # simulate the file disappearing from linux storage
        File.delete(File.join(root, backup_file.storage_path))

        # request the restore route
        get restore_device_backup_run_backup_file_path(
          device,
          run,
          backup_file
        )

        # return to backup history with an alert
        assert_redirected_to device_backup_runs_path(device)
        assert_equal "Backup file is missing from storage.", flash[:alert]

        event = SecurityEvent.order(:id).last
        assert_equal "RESTORE_FILE_MISSING", event.event_type
        assert_equal users(:alice), event.user
      ensure
        if previous_root
          ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
        else
          ENV.delete("PHONEVAULT_BACKUP_ROOT")
        end
      end
    end
  end

  test "restore redirects when the stored file is corrupted" do
    # log in as alice
    sign_in_as users(:alice)

    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed)
    uploaded_file = fixture_file_upload("sample_backup.txt", "text/plain")

    # use temporary storage so the test does not touch real backup files
    Dir.mktmpdir("phonevault_corrupt_restore") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root

      begin
        # store a real backup file first
        backup_file = BackupStorage.new.store(
          uploaded_file,
          backup_run: run,
          original_filename: uploaded_file.original_filename
        )

        # change the stored bytes without updating the saved sha-256
        File.write(
          File.join(root, backup_file.storage_path),
          "corrupted contents"
        )

        # request the restore route
        get restore_device_backup_run_backup_file_path(
          device,
          run,
          backup_file
        )

        # return to backup history with an integrity warning
        assert_redirected_to device_backup_runs_path(device)
        assert_equal "Backup file failed integrity verification.", flash[:alert]

        event = SecurityEvent.order(:id).last
        assert_equal "RESTORE_FILE_CORRUPTED", event.event_type
        assert_equal users(:alice), event.user
      ensure
        if previous_root
          ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
        else
          ENV.delete("PHONEVAULT_BACKUP_ROOT")
        end
      end
    end
  end

  test "delete requires login" do
    delete device_backup_run_backup_file_path(devices(:alice_phone), 1, 1)
    assert_redirected_to login_path
  end

  test "delete soft deletes only the owner's backup and leaves the file and metadata intact" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed)
    before_root = ENV["PHONEVAULT_BACKUP_ROOT"]

    Dir.mktmpdir("phonevault_trash") do |root|
      ENV["PHONEVAULT_BACKUP_ROOT"] = root
      begin
        file = BackupStorage.new.store(StringIO.new("keep these bytes"),
          backup_run: run, original_filename: "keep.txt")
        original_hash = file.sha256
        original_path = BackupStorage.new.path_for(file)
        old_deleted_at = file.deleted_at

        assert_no_difference "BackupFile.count" do
          delete device_backup_run_backup_file_path(device, run, file)
        end

        assert_redirected_to device_backup_runs_path(device)
        assert_equal "keep.txt moved to Trash.", flash[:notice]
        file.reload
        assert_not_nil file.deleted_at
        assert_operator file.deleted_at, :>=, old_deleted_at || Time.current - 1.minute
        assert_equal original_hash, file.sha256
        assert_equal original_path, BackupStorage.new.path_for(file)
        assert_equal "keep these bytes", File.binread(original_path)
        assert_equal "FILE_TRASHED", SecurityEvent.order(:id).last.event_type
      ensure
        before_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = before_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
      end
    end
  end

  test "delete cannot target another user's backup" do
    sign_in_as users(:alice)
    device = devices(:bob_phone)
    run = device.backup_runs.create!(status: :completed)
    file = run.backup_files.create!(original_filename: "secret.txt", size_bytes: 1,
      sha256: "a" * 64, storage_path: "#{run.id}/#{SecureRandom.uuid}")

    assert_no_difference "SecurityEvent.count" do
      delete device_backup_run_backup_file_path(device, run, file)
    end
    assert_response :not_found
    assert_nil file.reload.deleted_at
  end

  test "trashed backup files cannot be restored or previewed" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed)
    file = run.backup_files.create!(original_filename: "gone.png", size_bytes: PNG_BYTES.bytesize,
      sha256: Digest::SHA256.hexdigest(PNG_BYTES), storage_path: "#{run.id}/#{SecureRandom.uuid}",
      deleted_at: Time.current)

    get restore_device_backup_run_backup_file_path(device, run, file)
    assert_response :not_found
    get preview_device_backup_run_backup_file_path(device, run, file)
    assert_response :not_found
  end

  test "preview requires login" do
    get preview_device_backup_run_backup_file_path(devices(:alice_phone), 1, 1)

    assert_redirected_to login_path
  end

  test "preview serves a real image inline with a locked-down policy" do
    sign_in_as users(:alice)
    run = devices(:alice_phone).backup_runs.create!(status: :completed)

    with_backup_root do |storage|
      file = storage.store(StringIO.new(PNG_BYTES), backup_run: run, original_filename: "IMG_1.png")

      get preview_device_backup_run_backup_file_path(devices(:alice_phone), run, file)

      assert_response :success
      assert_equal "image/png", response.media_type
      assert_match(/\Ainline/, response.headers["Content-Disposition"])
      assert_match "default-src 'none'", response.headers["Content-Security-Policy"]
      assert_equal PNG_BYTES, response.body.b
    end
  end

  test "preview refuses a file that is not really an image" do
    sign_in_as users(:alice)
    run = devices(:alice_phone).backup_runs.create!(status: :completed)

    with_backup_root do |storage|
      file = storage.store(StringIO.new("<html><script>alert(1)</script></html>"), backup_run: run, original_filename: "photo.png")

      get preview_device_backup_run_backup_file_path(devices(:alice_phone), run, file)

      assert_response :not_found
    end
  end

  test "preview cannot show another user's file" do
    sign_in_as users(:alice)
    run = devices(:bob_phone).backup_runs.create!(status: :completed)

    with_backup_root do |storage|
      file = storage.store(StringIO.new(PNG_BYTES), backup_run: run, original_filename: "bob.png")

      get preview_device_backup_run_backup_file_path(devices(:bob_phone), run, file)

      assert_response :not_found
    end
  end

  private

  PNG_BYTES = "\x89PNG\r\n\x1a\n".b + ("x" * 20)

  # points storage at a temporary folder so tests never touch real backups
  def with_backup_root
    Dir.mktmpdir("phonevault_preview") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root
      yield BackupStorage.new
    ensure
      ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
    end
  end

  def sign_in_as(user, password: "secret123")
    post login_path,
      params: {
        session: {
          username: user.username,
          password: password
        }
      }
  end
end

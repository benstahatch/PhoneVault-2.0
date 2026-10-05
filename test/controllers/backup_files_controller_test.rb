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
      ensure
        if previous_root
          ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
        else
          ENV.delete("PHONEVAULT_BACKUP_ROOT")
        end
      end
    end
  end

  private
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
    ensure
      if previous_root
        ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
      else
        ENV.delete("PHONEVAULT_BACKUP_ROOT")
      end
    end
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

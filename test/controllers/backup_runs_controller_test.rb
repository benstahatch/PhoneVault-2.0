require "test_helper"

class BackupRunsControllerTest < ActionDispatch::IntegrationTest
  test "index requires login" do
    get device_backup_runs_path(devices(:alice_phone))
    assert_redirected_to login_path
  end

  test "index 404s for a device that belongs to another user" do
    sign_in_as users(:alice)

    get device_backup_runs_path(devices(:bob_phone))

    assert_response :not_found
  end

  test "create stores the uploaded file and marks the run complete" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    file = fixture_file_upload("sample_backup.txt", "text/plain")

    assert_difference [ "BackupRun.count", "BackupFile.count" ], 1 do
      post device_backup_runs_path(device), params: { backup_run: { file: file } }
    end

    run = device.backup_runs.order(:created_at).last
    assert run.completed?
    assert_equal "sample_backup.txt", run.backup_files.last.original_filename
    assert_equal Digest::SHA256.file(file_fixture("sample_backup.txt")).hexdigest, run.backup_files.last.sha256
    assert_redirected_to device_backup_runs_path(device)
  end

  test "create cannot be used against another user's device" do
    sign_in_as users(:alice)
    file = fixture_file_upload("sample_backup.txt", "text/plain")

    assert_no_difference [ "BackupRun.count", "BackupFile.count" ] do
      post device_backup_runs_path(devices(:bob_phone)), params: { backup_run: { file: file } }
    end

    assert_response :not_found
  end

  test "create re-renders the form when no file is chosen" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)

    assert_no_difference [ "BackupRun.count", "BackupFile.count" ] do
      post device_backup_runs_path(device), params: { backup_run: { file: "" } }
    end

    assert_response :unprocessable_entity
    assert_match "Choose a file to upload", response.body
  end


  test "create marks the backup run failed when storage fails" do
  sign_in_as users(:alice)

  device = devices(:alice_phone)
  file = fixture_file_upload("sample_backup.txt", "text/plain")

  Dir.mktmpdir("phonevault_failed_storage") do |root|
    blocked_path = File.join(root, "not_a_directory")
    File.write(blocked_path, "block storage here")

    previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = blocked_path

    begin
      assert_difference("BackupRun.count", 1) do
        assert_no_difference("BackupFile.count") do
          post device_backup_runs_path(device),
            params: { backup_run: { file: file } }
        end
      end

      run = device.backup_runs.order(:created_at).last

      assert run.failed?
      assert_redirected_to device_backup_runs_path(device)
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

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

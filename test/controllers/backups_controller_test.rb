require "test_helper"

class BackupsControllerTest < ActionDispatch::IntegrationTest
  # Authentication tests
  # Make sure logged-out users cannot access backup pages.

  test "new requires login" do
    get new_device_backup_path(devices(:alice_phone))

    assert_redirected_to login_path
  end

  test "new shows the backup form for the current user's device" do
    sign_in_as users(:alice)

    get new_device_backup_path(devices(:alice_phone))

    assert_response :success
    assert_match devices(:alice_phone).name, response.body
    assert_match "Choose a file", response.body
  end

  # Successful upload tests: sign in as Alice -> load test/fixtures/files/note.txt->
  # pretend it came from a browser upload -> POST it to Alice's device backup route
  # -> expect one BackupRun and one BackupFile
  # Make sure a valid upload creates a BackupRun and BackupFile.

test "create stores an uploaded file for the current user's device" do
  sign_in_as users(:alice)

  uploaded_file = fixture_file_upload(
    "note.txt",
    "text/plain"
  )

  Dir.mktmpdir("backups_controller_test") do |root|
    previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = root

    begin
      assert_difference("BackupRun.count", 1) do
        assert_difference("BackupFile.count", 1) do
          post device_backups_path(devices(:alice_phone)),
            params: { file: uploaded_file }
        end
      end
    ensure
      if previous_root
        ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
      else
        ENV.delete("PHONEVAULT_BACKUP_ROOT")
      end
    end
  end
end
  # Authorization / ownership tests
  # Make sure one user cannot upload files to another user's device.

  test "new refuses another user's device" do
    sign_in_as users(:alice)

    get new_device_backup_path(devices(:bob_phone))

    assert_response :not_found
  end

  # Failure tests
  # Make sure invalid or failed uploads do not leave bad records behind.

  private

  # Helper used by tests that need an authenticated user.
  # This keeps the login code from being repeated in every test.
  def sign_in_as(user, password: "secret123")
    post login_path, params: {
      session: {
        username: user.username,
        password: password
      }
    }
  end
end

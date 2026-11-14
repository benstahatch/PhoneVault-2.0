require "test_helper"

class BackupRunsControllerTest < ActionDispatch::IntegrationTest
  test "history displays file metadata and restore links alongside failed runs" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    completed = device.backup_runs.create!(status: :completed,
      started_at: 2.minutes.ago, completed_at: 1.minute.ago)
    files = [ "notes.txt", "photo.jpg" ].map do |name|
      completed.backup_files.create!(original_filename: name, size_bytes: 2048,
        sha256: "a" * 64, storage_path: "#{completed.id}/#{SecureRandom.uuid}")
    end
    device.backup_runs.create!(status: :failed, completed_at: Time.current)

    get device_backup_runs_path(device)

    assert_response :success
    assert_select "tbody tr", count: 3
    assert_select "tbody tr:first-child", text: /Backup failed\. No files were stored\./
    assert_select ".backup-status--completed", text: "Completed"
    assert_select "td", text: "2 KB", count: 2
    assert_select "details code", text: "a" * 64, count: 2
    assert_select "time[datetime=?]", completed.created_at.iso8601
    assert_select "time[datetime=?]", completed.started_at.iso8601
    assert_select "time[datetime=?]", completed.completed_at.iso8601
    files.each do |file|
      assert_select ".backup-file-details strong", text: file.original_filename
      assert_select "a[href=?]", restore_device_backup_run_backup_file_path(device, completed, file), text: "Restore"
    end
  end

  test "history preloads files and excludes other devices and users" do
    device = devices(:alice_phone)
    3.times do |i|
      run = device.backup_runs.create!(status: :completed, created_at: Time.current - i.minutes)
      run.backup_files.create!(original_filename: "owned-#{i}.txt", size_bytes: 1024,
        sha256: "a" * 64, storage_path: "#{run.id}/file")
    end
    [ devices(:alice_laptop), devices(:bob_phone) ].each do |other_device|
      run = other_device.backup_runs.create!(status: :completed)
      run.backup_files.create!(original_filename: "excluded-#{other_device.id}.txt", size_bytes: 1,
        sha256: "b" * 64, storage_path: "#{run.id}/file")
    end
    sign_in_as users(:alice)
    file_queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      file_queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM `backup_files`/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get device_backup_runs_path(device)
    end

    assert_response :success
    assert_select ".backup-file-details strong", count: 3
    assert_no_match "excluded-", response.body
    assert_equal 1, file_queries.size, "All history files should be loaded in one query"
  end

  test "unfinished runs without files show their statuses and no restore links" do
    device = devices(:alice_phone)
    device.backup_runs.create!(status: :pending)
    device.backup_runs.create!(status: :running, started_at: Time.current)
    sign_in_as users(:alice)

    get device_backup_runs_path(device)

    assert_response :success
    assert_select ".backup-status--pending", text: "Pending"
    assert_select ".backup-status--running", text: "Running"
    assert_select "td", text: "No files stored yet.", count: 2
    assert_select "a", text: "Restore", count: 0
  end

  test "history restore link downloads the original stored bytes" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed, completed_at: Time.current)
    upload = fixture_file_upload("sample_backup.txt", "text/plain")
    previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]

    Dir.mktmpdir("phonevault_history_restore") do |root|
      begin
        ENV["PHONEVAULT_BACKUP_ROOT"] = root
        file = BackupStorage.new.store(upload, backup_run: run, original_filename: upload.original_filename)
        get device_backup_runs_path(device)
        link = css_select("a").find { |element| element["aria-label"] == "Restore #{file.original_filename}" }
        assert link, "History should render a restore link for the file"
        get link["href"]
        assert_response :success
        assert_equal File.binread(file_fixture("sample_backup.txt")), response.body
        assert_includes response.headers["Content-Disposition"], "attachment"
      ensure
        previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
      end
    end
  end

  test "history explains when no backups exist" do
    sign_in_as users(:alice)

    get device_backup_runs_path(devices(:alice_phone))

    assert_response :success
    assert_select "table", count: 0
    assert_match "No backups yet. Upload a file to create your first backup.", response.body
  end

  test "history and upload pages use styled buttons" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)

    get device_backup_runs_path(device)
    assert_select "a.rounded-lg[href='#{new_device_backup_run_path(device)}']", text: "Upload a file"
    assert_select "a.rounded-lg[href='#{devices_path}']", text: "Back to your devices"

    get new_device_backup_run_path(device)
    assert_select "input[type=submit][value='Upload'].rounded-lg"
    assert_select "a.rounded-lg[href='#{device_backup_runs_path(device)}']", text: "Back to backups"
  end

  test "upload page wires the file field to a hidden preview panel" do
    sign_in_as users(:alice)

    get new_device_backup_run_path(devices(:alice_phone))

    assert_select "[data-controller='file-preview']" do
      assert_select "input[type=file][data-file-preview-target='input'][data-action='change->file-preview#show']"
      assert_select "[data-file-preview-target='panel'][hidden]"
      %w[image badge name size].each { |target| assert_select "[data-file-preview-target='#{target}']" }
    end

    # a display class like flex would override the hidden attribute and show an empty panel
    css_select("[data-file-preview-target][hidden]").each do |element|
      assert_no_match(/\b(flex|grid|block|inline-flex)\b/, element["class"].to_s)
    end
  end

  test "history shows image thumbnails, text excerpts, and badges" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed)

    Dir.mktmpdir("phonevault_history_preview") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root
      storage = BackupStorage.new
      photo = storage.store(StringIO.new("\x89PNG\r\n\x1a\n".b + "x" * 20), backup_run: run, original_filename: "IMG_1.png")
      storage.store(StringIO.new("<b>milk</b>\neggs\n"), backup_run: run, original_filename: "groceries.txt")
      storage.store(StringIO.new("%PDF-1.7"), backup_run: run, original_filename: "scan.pdf")

      get device_backup_runs_path(device)

      assert_select "img[src='#{preview_device_backup_run_backup_file_path(device, run, photo)}'][loading=lazy]"
      # the text is escaped, so a tag inside a file can't change the page
      assert_select "pre", text: "<b>milk</b>\neggs"
      assert_select "b", text: "milk", count: 0
      assert_select "div[aria-hidden=true]", text: "PDF"
    ensure
      ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
    end
  end

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

    assert_difference [ "BackupRun.count", "BackupFile.count", "SecurityEvent.count" ], 1 do
      post device_backup_runs_path(device), params: { backup_run: { file: file } }
    end

    run = device.backup_runs.order(:created_at).last
    assert run.completed?
    assert_equal "sample_backup.txt", run.backup_files.last.original_filename
    assert_equal Digest::SHA256.file(file_fixture("sample_backup.txt")).hexdigest, run.backup_files.last.sha256
    assert_redirected_to device_backup_runs_path(device)

    event = SecurityEvent.order(:id).last
    assert_equal "BACKUP_SUCCESS", event.event_type
    assert_equal users(:alice), event.user
  end

  test "a failure to record BACKUP_SUCCESS does not mark a stored backup failed" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)
    file = fixture_file_upload("sample_backup.txt", "text/plain")

    # temporarily make every security event save fail, like a database hiccup would
    SecurityEvent.define_singleton_method(:create!) do |*|
      raise ActiveRecord::ActiveRecordError, "simulated database failure"
    end

    begin
      assert_raises(ActiveRecord::ActiveRecordError) do
        post device_backup_runs_path(device), params: { backup_run: { file: file } }
      end
    ensure
      # put the real create! back so other tests aren't affected
      SecurityEvent.singleton_class.remove_method(:create!)
    end

    run = device.backup_runs.order(:created_at).last
    assert run.completed?
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

    assert_no_difference [ "BackupRun.count", "BackupFile.count", "SecurityEvent.count" ] do
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
      assert_difference([ "BackupRun.count", "SecurityEvent.count" ], 1) do
        assert_no_difference("BackupFile.count") do
          post device_backup_runs_path(device),
            params: { backup_run: { file: file } }
        end
      end

      run = device.backup_runs.order(:created_at).last

      assert run.failed?
      assert_redirected_to device_backup_runs_path(device)

      event = SecurityEvent.order(:id).last
      assert_equal "BACKUP_FAILED", event.event_type
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

  test "create rejects a file over the upload limit and records BACKUP_FAILED" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)

    # 1 MB is the smallest limit the setting allows, so upload one byte more
    file = Rack::Test::UploadedFile.new(
      StringIO.new("a" * (1.megabyte + 1)), "text/plain", original_filename: "too_big.txt"
    )

    previous_limit = ENV["PHONEVAULT_MAX_UPLOAD_MB"]
    ENV["PHONEVAULT_MAX_UPLOAD_MB"] = "1"

    begin
      assert_difference([ "BackupRun.count", "SecurityEvent.count" ], 1) do
        assert_no_difference("BackupFile.count") do
          post device_backup_runs_path(device), params: { backup_run: { file: file } }
        end
      end
    ensure
      ENV["PHONEVAULT_MAX_UPLOAD_MB"] = previous_limit
    end

    assert device.backup_runs.order(:created_at).last.failed?
    assert_redirected_to device_backup_runs_path(device)
    assert_equal "File is larger than the 1 MB upload limit.", flash[:alert]
    assert_equal "BACKUP_FAILED", SecurityEvent.order(:id).last.event_type
  end

  private

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

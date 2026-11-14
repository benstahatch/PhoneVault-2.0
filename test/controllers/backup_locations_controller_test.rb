require "test_helper"

class BackupLocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @temporary = Dir.mktmpdir("phonevault_locations")
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = @temporary
    @device = devices(:alice_phone)
    @root = BackupDirectory.for_user(users(:alice)).root
    @folder = @root.join("Photos 2026")
    @folder.mkdir
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    FileUtils.remove_entry(@temporary)
  end

  test "folder endpoints require login and device ownership" do
    get directories_device_backup_location_path(@device)
    assert_redirected_to login_path
    post validate_path_device_backup_location_path(@device), params: { path: @folder.to_s }
    assert_redirected_to login_path
    sign_in
    get directories_device_backup_location_path(devices(:bob_phone))
    assert_response :not_found
    post validate_path_device_backup_location_path(devices(:bob_phone)), params: { path: @folder.to_s }
    assert_response :not_found
  end

  test "browse lists actual folders and allows selecting one" do
    sign_in
    get directories_device_backup_location_path(@device)
    assert_response :success
    assert_select "a", text: "Photos 2026"
    assert_select "a", text: "Up", count: 1
    get directories_device_backup_location_path(@device), params: { path: @folder.to_s }
    assert_select "a", text: "Up", count: 1
    get new_device_backup_run_path(@device), params: { save_path: @folder.to_s }
    assert_select "input[name='backup_run[save_path]'][value=?]", @folder.to_s
  end

  test "test path reports writable and missing folders" do
    sign_in
    post validate_path_device_backup_location_path(@device), params: { path: @folder.to_s }, as: :json
    assert_response :success
    assert_equal "Directory exists and is writable.", response.parsed_body["message"]
    assert_empty @folder.children
    other = @root.join("missing")
    post validate_path_device_backup_location_path(@device), params: { path: other.to_s }, as: :json
    assert_response :unprocessable_entity
    get directories_device_backup_location_path(@device), params: { path: other.to_s }
    assert_redirected_to new_device_backup_run_path(@device)
  end

  test "upload uses selected folder and restores it after a later upload uses another folder" do
    sign_in
    upload_to(@folder)
    run = @device.backup_runs.order(:id).last
    file = run.backup_files.sole
    assert_equal @folder.to_s, run.storage_root
    assert @folder.join(file.storage_path).file?
    upload_to(@root)
    get restore_device_backup_run_backup_file_path(@device, run, file)
    assert_response :success
    assert_equal File.binread(file_fixture("sample_backup.txt")), response.body
  end

  test "invalid save paths do not create backup records and remain in the form" do
    sign_in
    bad_path = @root.join("missing").to_s
    assert_no_difference [ "BackupRun.count", "BackupFile.count" ] do
      upload_to(bad_path)
    end
    assert_response :unprocessable_entity
    assert_select "input[name='backup_run[save_path]'][value=?]", bad_path
    assert_match "Directory does not exist", response.body
  end

  test "saved location cannot redirect restore into another account" do
    sign_in
    upload_to(@folder)
    run = @device.backup_runs.order(:id).last
    run.update!(storage_root: nil, backup_subdirectory: "users/#{users(:bob).id}")
    get restore_device_backup_run_backup_file_path(@device, run, run.backup_files.sole)
    assert_redirected_to device_backup_runs_path(@device)
    assert_equal "Choose a folder inside your backup storage.", flash[:alert]
  end

  test "upload to Downloads outside the default root succeeds and displays green confirmation" do
    sign_in
    Dir.mktmpdir("phonevault_downloads") do |external|
      destination = Pathname(external).realpath.join("TEST")
      destination.mkdir
      post validate_path_device_backup_location_path(@device), params: { path: destination.to_s }, as: :json
      assert_response :success
      get directories_device_backup_location_path(@device), params: { path: destination.to_s }, as: :json
      assert_equal destination.to_s, response.parsed_body["path"]
      assert_equal destination.parent.to_s, response.parsed_body["parent"]

      upload_to(destination)
      assert_redirected_to device_backup_runs_path(@device)
      follow_redirect!
      assert_select "[role=status].bg-green-50.text-green-800", text: "File uploaded successfully. Backup completed."
      run = @device.backup_runs.order(:id).last
      file = run.backup_files.sole
      assert_equal destination.to_s, run.storage_root
      assert destination.join(file.storage_path).file?

      # Explicit destinations must not depend on the default root being available.
      ENV["PHONEVAULT_BACKUP_ROOT"] = File.join(@temporary, "different-default")
      get restore_device_backup_run_backup_file_path(@device, run, file)
      assert_response :success
      assert_equal File.binread(file_fixture("sample_backup.txt")), response.body
    end
  end

  test "existing relative-location backups still restore" do
    sign_in
    relative = @folder.relative_path_from(Pathname(@temporary).realpath).to_s
    run = @device.backup_runs.create!(status: :completed, backup_subdirectory: relative)
    file = BackupStorage.new(root: @folder).store(
      StringIO.new("older backup"), backup_run: run, original_filename: "older.txt"
    )
    get restore_device_backup_run_backup_file_path(@device, run, file)
    assert_response :success
    assert_equal "older backup", response.body
  end

  private

  def sign_in
    post login_path, params: { session: { username: users(:alice).username, password: "secret123" } }
  end

  def upload_to(folder)
    post device_backup_runs_path(@device), params: { backup_run: {
      file: fixture_file_upload("sample_backup.txt", "text/plain"), save_path: folder.to_s
    } }
  end
end

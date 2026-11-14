require "test_helper"

class BackupSavePathTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1200, 900 ]

  setup do
    @temporary = Dir.mktmpdir("phonevault_browser")
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = @temporary
    @root = BackupDirectory.for_user(users(:alice)).root
    @external = Dir.mktmpdir("phonevault_downloads_browser")
    @folder = Pathname(@external).realpath.join("Family photos")
    @folder.mkdir
    Rails.cache.clear
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    FileUtils.remove_entry(@temporary)
    FileUtils.remove_entry(@external)
  end

  test "browse preserves file selection and uploads into the tested directory" do
    visit login_path
    fill_in "Username", with: "alice"
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_text "Dashboard"
    visit new_device_backup_run_path(devices(:alice_phone))
    upload_path = File.join(@temporary, "sample_backup.txt")
    FileUtils.cp(file_fixture("sample_backup.txt"), upload_path)
    attach_file "File", upload_path
    fill_in "Save path", with: Pathname(@external).realpath.to_s
    click_on "Browse folders"
    within "dialog[open]" do
      click_on "Family photos"
      assert_text @folder.to_s
      click_on "Use this folder"
    end
    assert_field "Save path", with: @folder.to_s
    assert_equal "sample_backup.txt", page.evaluate_script("document.querySelector('input[type=file]').files[0].name")
    click_on "Test path"
    assert_text "Directory exists and is writable."
    click_on "Upload"
    assert_selector "[role=status].bg-green-50.text-green-800", text: "File uploaded successfully.", wait: 10
    assert_text "sample_backup.txt"
    assert_text "Save folder:"
    file = devices(:alice_phone).backup_runs.order(:id).last.backup_files.sole
    assert @folder.join(file.storage_path).file?
  end
end

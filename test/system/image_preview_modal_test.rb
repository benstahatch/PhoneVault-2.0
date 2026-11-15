require "test_helper"

class ImagePreviewModalTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1200, 900 ]

  setup do
    @root = Dir.mktmpdir("phonevault_image_modal")
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = @root
    Rails.cache.clear
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    FileUtils.remove_entry(@root)
  end

  test "opens full image in accessible modal and closes with button or Escape" do
    device = devices(:alice_phone)
    run = device.backup_runs.create!(status: :completed, storage_root: @root)
    image_bytes = "\x89PNG\r\n\x1a\n".b + ("x" * 20)
    file = BackupStorage.new.store(StringIO.new(image_bytes), backup_run: run, original_filename: "portrait.png")

    visit login_path
    fill_in "Username", with: "alice"
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_text "Dashboard"
    visit device_backup_runs_path(device)
    trigger = find("button[data-image-preview-url-param]")
    assert_equal "Preview portrait.png", trigger["aria-label"]
    assert_equal "", trigger.find("img")["alt"]
    trigger.click

    dialog = find("dialog[open]")
    assert_equal "portrait.png", dialog.find("h2").text
    image = dialog.find("img")
    assert_equal "Preview of portrait.png", image["alt"]
    assert_equal preview_device_backup_run_backup_file_path(device, run, file), URI.parse(image["src"]).path
    assert dialog["aria-modal"]
    assert_equal "Close", dialog.find_button("Close").text

    dialog.find_button("Close").click
    assert_no_selector "dialog[open]"
    assert_equal trigger[:id], page.evaluate_script("document.activeElement.id")

    trigger.click
    page.active_element.send_keys(:escape)
    assert_no_selector "dialog[open]"
  end
end

require "test_helper"

class DevicesControllerTest < ActionDispatch::IntegrationTest
  test "index requires login" do
    get devices_path
    assert_redirected_to login_path
  end

  test "index lists only the current user's devices" do
    sign_in_as users(:alice)

    get devices_path

    assert_response :success
    assert_match devices(:alice_phone).name, response.body
    assert_match devices(:alice_laptop).name, response.body
    assert_no_match devices(:bob_phone).name, response.body
  end

  test "index shows its links as buttons" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)

    get devices_path

    assert_select "a.rounded-lg[href='#{new_device_path}']", text: "Register a device"
    assert_select "a.rounded-lg[href='#{dashboard_path}']", text: "Back to dashboard"
    assert_select "a.rounded-lg[href='#{device_backup_runs_path(device)}']", text: "Backups"
    assert_select "a.rounded-lg[href='#{new_device_backup_run_path(device)}']", text: "Upload"
  end

  test "register form uses styled buttons" do
    sign_in_as users(:alice)

    get new_device_path

    assert_response :success
    assert_select "input[type=submit][value='Register device'].rounded-lg"
    assert_select "a.rounded-lg[href='#{devices_path}']", text: "Back to your devices"
  end

  test "create registers a device for the current user" do
    sign_in_as users(:alice)

    assert_difference("Device.count", 1) do
      post devices_path, params: { device: { name: "Alice Tablet", device_type: "tablet" } }
    end

    device = Device.last
    assert_equal users(:alice), device.user
    assert_redirected_to devices_path
  end

  test "create records DEVICE_REGISTERED for the current user" do
    sign_in_as users(:alice)

    assert_difference("SecurityEvent.count", 1) do
      post devices_path, params: { device: { name: "Alice Tablet", device_type: "tablet" } }
    end

    event = SecurityEvent.order(:id).last
    assert_equal "DEVICE_REGISTERED", event.event_type
    assert_equal users(:alice), event.user
  end

  test "create records no event when the device is invalid" do
    sign_in_as users(:alice)

    assert_no_difference("SecurityEvent.count") do
      post devices_path, params: { device: { name: "", device_type: "tablet" } }
    end

    assert_response :unprocessable_entity
  end

  test "create ignores an attempt to assign the device to another user" do
    sign_in_as users(:alice)

    post devices_path, params: { device: { name: "Sneaky Device", device_type: "phone", user_id: users(:bob).id } }

    assert_equal users(:alice), Device.last.user
  end

  test "create re-renders the form when the device is invalid" do
    sign_in_as users(:alice)

    assert_no_difference("Device.count") do
      post devices_path, params: { device: { name: "", device_type: "phone" } }
    end

    assert_response :unprocessable_entity
    assert_match "prevented this device from being registered", response.body
  end

  test "create rejects a name already used by the same user" do
    sign_in_as users(:alice)

    assert_no_difference("Device.count") do
      post devices_path, params: { device: { name: devices(:alice_phone).name, device_type: "phone" } }
    end

    assert_response :unprocessable_entity
  end

  test "index shows a rename button for each device" do
    sign_in_as users(:alice)

    get devices_path

    assert_select "a.rounded-lg[href='#{edit_device_path(devices(:alice_phone))}']", text: "Rename"
    assert_select "a.rounded-lg[href='#{edit_device_path(devices(:alice_laptop))}']", text: "Rename"
  end

  test "edit requires login" do
    get edit_device_path(devices(:alice_phone))
    assert_redirected_to login_path
  end

  test "edit shows the current name" do
    sign_in_as users(:alice)

    get edit_device_path(devices(:alice_phone))

    assert_response :success
    assert_select "input[name='device[name]'][value=?]", "Alice Pixel"
  end

  test "update renames the device" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)

    patch device_path(device), params: { device: { name: "Work Phone" } }

    assert_redirected_to devices_path
    assert_equal "Work Phone", device.reload.name
    follow_redirect!
    assert_match "Device renamed to Work Phone.", response.body
  end

  test "update records DEVICE_RENAMED for the current user" do
    sign_in_as users(:alice)

    assert_difference("SecurityEvent.count", 1) do
      patch device_path(devices(:alice_phone)), params: { device: { name: "Work Phone" } }
    end

    event = SecurityEvent.last
    assert_equal "DEVICE_RENAMED", event.event_type
    assert_equal users(:alice), event.user
  end

  test "update records no event when the rename is rejected" do
    sign_in_as users(:alice)

    assert_no_difference("SecurityEvent.count") do
      patch device_path(devices(:alice_phone)), params: { device: { name: "" } }
    end
  end

  test "update ignores attempts to change the device type or owner" do
    sign_in_as users(:alice)
    device = devices(:alice_phone)

    patch device_path(device), params: { device: { name: "Work Phone", device_type: "laptop", user_id: users(:bob).id } }

    device.reload
    assert_equal "Work Phone", device.name
    assert_equal "phone", device.device_type
    assert_equal users(:alice), device.user
  end

  test "update rejects a blank name" do
    sign_in_as users(:alice)

    patch device_path(devices(:alice_phone)), params: { device: { name: "  " } }

    assert_response :unprocessable_entity
    assert_equal "Alice Pixel", devices(:alice_phone).reload.name
  end

  test "update rejects a name already used by another of the user's devices" do
    sign_in_as users(:alice)

    patch device_path(devices(:alice_phone)), params: { device: { name: "alice thinkpad" } }

    assert_response :unprocessable_entity
    assert_equal "Alice Pixel", devices(:alice_phone).reload.name
  end

  test "edit and update 404 for another user's device" do
    sign_in_as users(:alice)
    device = devices(:bob_phone)

    get edit_device_path(device)
    assert_response :not_found

    patch device_path(device), params: { device: { name: "Stolen" } }
    assert_response :not_found
    assert_equal "Bob iPhone", device.reload.name
  end

  private

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

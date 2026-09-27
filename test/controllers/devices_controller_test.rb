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

  test "create registers a device for the current user" do
    sign_in_as users(:alice)

    assert_difference("Device.count", 1) do
      post devices_path, params: { device: { name: "Alice Tablet", device_type: "tablet" } }
    end

    device = Device.last
    assert_equal users(:alice), device.user
    assert_redirected_to devices_path
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

  private

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

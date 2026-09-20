require "test_helper"

class DeviceTest < ActiveSupport::TestCase
 test "a name is required" do
    device = Device.new(user: users(:alice), device_type: "phone")
    assert_not device.valid?
    assert device.errors[:name].any?
  end

  test "a user is required" do
    device = Device.new(name: "Orphan", device_type: "phone")
    assert_not device.valid?
    assert device.errors[:user].any?
  end

  test "every defined device_type is accepted" do
    %w[phone laptop tablet desktop other].each_with_index do |type, i|
      device = Device.new(user: users(:bob), name: "Test Device #{i}", device_type: type)
      assert device.valid?, "expected #{type} to be valid: #{device.errors.full_messages.join(', ')}"
    end
  end

  test "an unknown device_type is rejected" do
    device = Device.new(user: users(:bob), name: "Mystery", device_type: "smartwatch")
    assert_not device.valid?
    assert device.errors[:device_type].any?
  end

  test "a name must be unique per user, ignoring case" do
    device = Device.new(user: users(:alice), name: "alice pixel", device_type: "phone")
    assert_not device.valid?
    assert device.errors[:name].any?
  end

  test "two users may each have a device with the same name" do
    device = Device.new(user: users(:bob), name: "Alice Pixel", device_type: "phone")
    assert device.valid?, device.errors.full_messages.join(", ")
  end

  test "surrounding whitespace is stripped from the name" do
    device = Device.new(name: "  Spaced Out  ")
    assert_equal "Spaced Out", device.name
  end

  test "a name longer than 100 characters is rejected" do
    device = Device.new(user: users(:bob), name: "x" * 101, device_type: "phone")
    assert_not device.valid?
    assert device.errors[:name].any?
  end

  test "a device with backup runs cannot be destroyed" do
    device = devices(:alice_phone)
    BackupRun.create!(device: device, status: "completed")
    assert_not device.destroy
    assert device.errors[:base].any?
    assert Device.exists?(device.id)
  end

  test "a device with no backup runs can be destroyed" do
    device = devices(:bob_phone)
    assert device.destroy
    assert_not Device.exists?(device.id)
  end
end

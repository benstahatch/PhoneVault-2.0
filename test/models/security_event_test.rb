require "test_helper"

class SecurityEventTest < ActiveSupport::TestCase
  test "an event type is required" do
    event = SecurityEvent.new(user: users(:alice))
    assert_not event.valid?
    assert event.errors[:event_type].any?
  end

  test "an event type longer than 50 characters is rejected" do
    event = SecurityEvent.new(user: users(:alice), event_type: "x" * 51)
    assert_not event.valid?
    assert event.errors[:event_type].any?
  end

  test "an event may exist without a user" do
    event = SecurityEvent.new(event_type: "failed_login", ip_address: "203.0.113.5")
    assert event.valid?, event.errors.full_messages.join(", ")
  end

  test "an event may belong to a user" do
    event = SecurityEvent.new(user: users(:alice), event_type: "login")
    assert event.valid?, event.errors.full_messages.join(", ")
  end

  test "an ip address is optional" do
    event = SecurityEvent.new(event_type: "login", ip_address: nil)
    assert event.valid?, event.errors.full_messages.join(", ")
  end

  test "an ip address may be up to 45 characters" do
    event = SecurityEvent.new(event_type: "login", ip_address: "x" * 45)
    assert event.valid?, event.errors.full_messages.join(", ")
  end

  test "an ip address longer than 45 characters is rejected" do
    event = SecurityEvent.new(event_type: "login", ip_address: "x" * 46)
    assert_not event.valid?
    assert event.errors[:ip_address].any?
  end
end

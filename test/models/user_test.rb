
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a valid user is accepted" do
    user = User.new(username: "newcomer", display_name: "New Comer", password: "secret123")
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "a username is required" do
    user = User.new(display_name: "No Name", password: "secret123")
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "a username shorter than 3 characters is rejected" do
    user = User.new(username: "ab", display_name: "Too Short", password: "secret123")
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "a username longer than 50 characters is rejected" do
    user = User.new(username: "x" * 51, display_name: "Too Long", password: "secret123")
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "a username may not contain spaces or punctuation" do
    user = User.new(username: "bad name!", display_name: "Bad Name", password: "secret123")
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "a username is stripped and downcased" do
    user = User.new(username: "  MixedCase  ")
    assert_equal "mixedcase", user.username
  end

  test "usernames are unique regardless of case" do
    user = User.new(username: "ALICE", display_name: "Impostor", password: "secret123")
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "a display name is required" do
    user = User.new(username: "nodisplay", password: "secret123")
    assert_not user.valid?
    assert user.errors[:display_name].any?
  end

  test "a password shorter than 8 characters is rejected" do
    user = User.new(username: "shortpw", display_name: "Short PW", password: "sevench")
    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "an existing user stays valid without supplying a password" do
    assert users(:alice).valid?, users(:alice).errors.full_messages.join(", ")
  end

  test "authentication succeeds with the right password and fails with the wrong one" do
    assert users(:alice).authenticate("secret123")
    assert_not users(:alice).authenticate("wrongpass")
  end

  test "a user has many devices" do
    assert_equal 2, users(:alice).devices.count
  end

  test "a user with devices cannot be destroyed" do
    user = users(:alice)
    assert_not user.destroy
    assert user.errors[:base].any?
    assert User.exists?(user.id)
  end

  test "a user with no devices can be destroyed" do
    user = User.create!(username: "loner", display_name: "Loner", password: "secret123")
    assert user.destroy
    assert_not User.exists?(user.id)
  end

  test "destroying a user leaves their security events behind with no owner" do
    user = User.create!(username: "audited", display_name: "Audited", password: "secret123")
    event = SecurityEvent.create!(user: user, event_type: "login")
    assert user.destroy
    assert_nil event.reload.user_id
  end
end

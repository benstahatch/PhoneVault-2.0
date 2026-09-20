require "test_helper"

class BackupRunTest < ActiveSupport::TestCase
  test "every defined status is accepted" do
    %w[pending running completed failed].each do |status|
      run = BackupRun.new(device: devices(:alice_phone), status: status)
      assert run.valid?, "expected #{status} to be valid: #{run.errors.full_messages.join(', ')}"
    end
  end

  test "a status outside the enum is rejected" do
    run = BackupRun.new(device: devices(:alice_phone), status: "paused")
    assert_not run.valid?
    assert run.errors[:status].any?
  end

  test "a status is required" do
    run = BackupRun.new(device: devices(:alice_phone))
    assert_not run.valid?
    assert run.errors[:status].any?
  end

  test "status predicates reflect the current status" do
    run = BackupRun.new(device: devices(:alice_phone), status: "running")
    assert run.running?
    assert_not run.completed?
  end

  test "a backup run requires a device" do
    run = BackupRun.new(status: "pending")
    assert_not run.valid?
    assert run.errors[:device].any?
  end
end

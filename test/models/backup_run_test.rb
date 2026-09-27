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

  test "a backup run with files cannot be destroyed" do
    run = BackupRun.create!(device: devices(:alice_phone), status: "completed")
    BackupFile.create!(
      backup_run: run,
      original_filename: "photo.jpg",
      storage_path: "/data/photo.jpg",
      size_bytes: 1024,
      sha256: "a" * 64
    )
    assert_not run.destroy
    assert run.errors[:base].any?
    assert BackupRun.exists?(run.id)
  end

  test "a backup run with no files can be destroyed" do
    run = BackupRun.create!(device: devices(:alice_phone), status: "pending")
    assert run.destroy
    assert_not BackupRun.exists?(run.id)
  end

  test "start! marks the run as running and records the start time" do
    run = BackupRun.create!(device: devices(:alice_phone), status: "pending")
    run.start!
    assert run.reload.running?
    assert_not_nil run.started_at
    assert_nil run.completed_at
  end

  test "complete! marks the run as completed and records the finish time" do
    run = BackupRun.create!(device: devices(:alice_phone), status: "running")
    run.complete!
    assert run.reload.completed?
    assert_not_nil run.completed_at
  end

  test "fail! marks the run as failed and records the finish time" do
    run = BackupRun.create!(device: devices(:alice_phone), status: "running")
    run.fail!
    assert run.reload.failed?
    assert_not_nil run.completed_at
  end
end

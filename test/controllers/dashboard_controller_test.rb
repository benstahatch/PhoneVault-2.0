require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "dashboard requires login" do
    get dashboard_path
    assert_redirected_to login_path
  end

  test "totals and activity exclude other users and reflect new files" do
    alice_run = devices(:alice_phone).backup_runs.create!(status: :completed, completed_at: 1.hour.ago)
    bob_run = devices(:bob_phone).backup_runs.create!(status: :completed, completed_at: Time.current)
    add_file(alice_run, 1024)
    add_file(bob_run, 8192)
    sign_in_as(users(:alice))

    get dashboard_path
    assert_response :success
    assert_select "#device-count", text: "2"
    assert_select "#file-count", text: "1"
    assert_select "#stored-bytes", text: "1 KB"
    assert_select "time[datetime=?]", alice_run.completed_at.iso8601
    assert_select "a[href=?]", device_backup_runs_path(devices(:bob_phone)), count: 0
    assert_no_match devices(:bob_phone).name, response.body

    add_file(alice_run, 1024)
    get dashboard_path
    assert_select "#file-count", text: "2"
    assert_select "#stored-bytes", text: "2 KB"
  end

  test "new user sees zero totals and empty states" do
    user = User.create!(username: "newuser", display_name: "New User", password: "secret123")
    sign_in_as(user)
    get dashboard_path
    assert_response :success
    assert_select "#device-count", text: "0"
    assert_select "#file-count", text: "0"
    assert_select "#stored-bytes", text: "0 Bytes"
    assert_match "No successful backups yet.", response.body
    assert_match "No backup activity yet.", response.body
  end

  test "recent activity is limited to five newest runs and includes failures" do
    device = devices(:alice_phone)
    pending = 6.times.map { |i| device.backup_runs.create!(status: :pending, created_at: (i + 1).hours.ago) }
    failed = device.backup_runs.create!(status: :failed)
    sign_in_as(users(:alice))
    get dashboard_path
    assert_select ".dashboard-activity li", count: 5
    assert_select ".dashboard-activity li:first-child .backup-status", text: "Failed"
    assert_select ".dashboard-activity time" do |timestamps|
      assert_equal [ failed, *pending.first(4) ].map { |run| run.created_at.iso8601 },
        timestamps.map { |timestamp| timestamp["datetime"] }
    end
    assert_match "No successful backups yet.", response.body
  end

  test "totals include files across devices and runs without deduplicating equal sizes" do
    first = devices(:alice_phone).backup_runs.create!(status: :completed, completed_at: 2.days.ago)
    second = devices(:alice_phone).backup_runs.create!(status: :pending)
    third = devices(:alice_laptop).backup_runs.create!(status: :failed)
    add_file(first, 1.megabyte)
    add_file(first, 1.megabyte)
    add_file(second, 1.megabyte)
    add_file(third, 0)
    sign_in_as(users(:alice))

    get dashboard_path
    assert_select "#device-count", text: "2"
    assert_select "#file-count", text: "4"
    assert_select "#stored-bytes", text: "3 MB"

    add_file(third, 1.gigabyte - 3.megabytes)
    get dashboard_path
    assert_select "#file-count", text: "5"
    assert_select "#stored-bytes", text: "1 GB"
  end

  test "latest success uses completion time and excludes failed and unfinished runs" do
    device = devices(:alice_phone)
    latest = device.backup_runs.create!(status: :completed,
      created_at: 3.days.ago, completed_at: 1.hour.ago)
    device.backup_runs.create!(status: :completed, created_at: 2.days.ago, completed_at: 1.day.ago)
    device.backup_runs.create!(status: :failed, completed_at: Time.current)
    device.backup_runs.create!(status: :running)
    device.backup_runs.create!(status: :completed, completed_at: nil)
    devices(:bob_phone).backup_runs.create!(status: :completed, completed_at: Time.current)
    sign_in_as(users(:alice))

    get dashboard_path
    assert_select "#latest-successful-backup time", count: 1
    assert_select "#latest-successful-backup time[datetime=?]", latest.completed_at.iso8601
    assert_select "#latest-successful-backup a[href=?]", device_backup_runs_path(device)
  end

  test "registered devices without backups show zero file totals" do
    sign_in_as(users(:alice))
    get dashboard_path
    assert_select "#device-count", text: "2"
    assert_select "#file-count", text: "0"
    assert_select "#stored-bytes", text: "0 Bytes"
    assert_match "No successful backups yet.", response.body
    assert_match "No backup activity yet.", response.body
  end

  test "switching users scopes every dashboard section to the new session" do
    alice_run = devices(:alice_phone).backup_runs.create!(status: :completed, completed_at: Time.current)
    bob_run = devices(:bob_phone).backup_runs.create!(status: :completed, completed_at: 1.day.ago)
    add_file(alice_run, 8192)
    add_file(bob_run, 2048)
    sign_in_as(users(:alice))
    get dashboard_path
    assert_select "#stored-bytes", text: "8 KB"
    delete logout_path
    sign_in_as(users(:bob))

    get dashboard_path
    assert_response :success
    assert_select "#device-count", text: "1"
    assert_select "#file-count", text: "1"
    assert_select "#stored-bytes", text: "2 KB"
    assert_select ".dashboard-activity li", count: 1
    assert_select "#latest-successful-backup time[datetime=?]", bob_run.completed_at.iso8601
    assert_no_match devices(:alice_phone).name, response.body
    assert_select "a[href=?]", device_backup_runs_path(devices(:alice_phone)), count: 0
  end

  private

  def sign_in_as(user)
    post login_path, params: { session: { username: user.username, password: "secret123" } }
  end

  def add_file(run, size)
    run.backup_files.create!(original_filename: "sample.txt", size_bytes: size,
      sha256: "a" * 64, storage_path: "#{run.id}/#{SecureRandom.uuid}")
  end
end

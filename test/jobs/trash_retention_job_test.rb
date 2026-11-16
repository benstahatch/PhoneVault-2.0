require "test_helper"

class TrashRetentionJobTest < ActiveJob::TestCase
  setup do
    @environment = %w[
      PHONEVAULT_BACKUP_ROOT
      PHONEVAULT_TRASH_CLEANUP_ENABLED
    ].index_with { |key| ENV[key] }
    @root = Dir.mktmpdir("phonevault_trash_retention")
    ENV["PHONEVAULT_BACKUP_ROOT"] = @root
    ENV.delete("PHONEVAULT_TRASH_CLEANUP_ENABLED")

    @user = users(:alice)
    @user.update!(trash_retention_days: nil)
    @device = devices(:alice_phone)
    @run = @device.backup_runs.create!(status: :completed, storage_root: @root)
    @file = store_file(@run, "expired.jpg", "temporary image bytes")
    @file.update!(deleted_at: 31.days.ago)
  end

  teardown do
    @environment.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.remove_entry(@root)
  end

  test "retention defaults to Never and automatic cleanup stays disabled by default" do
    assert_nil @user.reload.trash_retention_days
    assert_not TrashRetention.cleanup_enabled?
  end

  test "disabled cleanup leaves expired files and records untouched" do
    @user.update!(trash_retention_days: 30)
    path = BackupStorage.for_run(@run).path_for(@file)

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      assert_empty TrashRetentionJob.perform_now
    end

    assert @file.reload.deleted_at.present?
    assert File.file?(path)
  end

  test "Never keeps expired Trash files even when server cleanup is enabled" do
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    path = BackupStorage.for_run(@run).path_for(@file)

    assert_empty TrashRetentionJob.perform_now

    assert @file.reload.deleted_at.present?
    assert File.file?(path)
  end

  test "dry run reports expired files without deleting bytes, records, or events" do
    @user.update!(trash_retention_days: 30)
    path = BackupStorage.for_run(@run).path_for(@file)

    assert_no_difference [ "BackupFile.count", "SecurityEvent.count" ] do
      result = TrashRetentionJob.perform_now(dry_run: true)
      assert_equal 1, result.length
      assert_equal "would_delete", result.first[:status]
      assert_equal "expired.jpg", result.first[:filename]
      assert_equal "alice", result.first[:owner]
    end

    assert @file.reload.deleted_at.present?
    assert_equal "temporary image bytes", File.binread(path)
  end

  test "enabled cleanup deletes only expired trashed files and records each success" do
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    @user.update!(trash_retention_days: 30)
    @run.update_column(:created_at, 365.days.ago)
    recent_file = store_file(@run, "recent.jpg", "recent bytes")
    recent_file.update!(deleted_at: 10.days.ago)
    active_file = store_file(@run, "active.jpg", "active bytes")
    active_path = BackupStorage.for_run(@run).path_for(active_file)
    old_trashed_path = BackupStorage.for_run(@run).path_for(@file)

    result = TrashRetentionJob.perform_now

    assert_equal [ "deleted" ], result.map { |item| item[:status] }
    assert_not BackupFile.exists?(@file.id)
    assert_not File.exist?(old_trashed_path)
    assert recent_file.reload.deleted_at.present?
    assert_equal "recent bytes", File.binread(BackupStorage.for_run(@run).path_for(recent_file))
    assert_nil active_file.reload.deleted_at
    assert_equal "active bytes", File.binread(active_path)

    event = SecurityEvent.order(:id).last
    assert_equal "FILE_PERMANENTLY_DELETED", event.event_type
    assert_equal @user.id, event.user_id
    assert_equal "BackupFile", event.subject_type
    assert_equal @file.id, event.subject_id
  end

  test "the user's retention period uses deleted_at as its cutoff" do
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    @user.update!(trash_retention_days: 60)
    recently_trashed = store_file(@run, "recently-trashed.txt", "new in trash")
    recently_trashed.update!(deleted_at: 59.days.ago)
    @file.update!(deleted_at: 61.days.ago)
    old_path = BackupStorage.for_run(@run).path_for(@file)

    result = TrashRetentionJob.perform_now

    assert_equal [ @file.id ], result.map { |item| item[:backup_file_id] }
    assert_not BackupFile.exists?(@file.id)
    assert_not File.exist?(old_path)
    assert recently_trashed.reload.deleted_at.present?
  end

  test "cleanup uses each owner's configured storage root" do
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    @user.update!(trash_retention_days: 30)
    other_root = Dir.mktmpdir("phonevault_other_owner_backups")
    other_run = devices(:bob_phone).backup_runs.create!(status: :completed, storage_root: other_root)
    users(:bob).update!(trash_retention_days: 60)
    other_file = store_file(other_run, "bob-expired.txt", "bob's bytes")
    other_file.update!(deleted_at: 61.days.ago)
    other_path = BackupStorage.for_run(other_run).path_for(other_file)

    result = TrashRetentionJob.perform_now

    assert_equal 2, result.length
    assert_equal [ @user.id, users(:bob).id ].sort,
      SecurityEvent.where(event_type: "FILE_PERMANENTLY_DELETED").pluck(:user_id).sort
    assert_not BackupFile.exists?(@file.id)
    assert_not BackupFile.exists?(other_file.id)
    assert_not File.exist?(other_path)
  ensure
    FileUtils.remove_entry(other_root) if other_root && File.exist?(other_root)
  end

  test "failed filesystem deletion retains the record and logs the error" do
    skip "root ignores directory permissions" if Process.uid.zero?
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    @user.update!(trash_retention_days: 30)
    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log_output)
    path = BackupStorage.for_run(@run).path_for(@file)
    File.chmod(0o500, path.dirname) # read-only folder: unlink raises Errno::EACCES

    result = TrashRetentionJob.perform_now

    assert_equal "failed", result.first[:status]
    assert @file.reload.deleted_at.present?
    assert File.file?(path)
    assert_match "Trash retention failed", log_output.string
  ensure
    File.chmod(0o700, path.dirname) if path
    Rails.logger = original_logger if original_logger
  end

  test "unsafe paths are skipped and logged without modifying outside files" do
    ENV["PHONEVAULT_TRASH_CLEANUP_ENABLED"] = "true"
    @user.update!(trash_retention_days: 30)
    outside_path = File.join(File.dirname(@root), "phonevault-retention-sentinel-#{SecureRandom.hex(6)}")
    File.binwrite(outside_path, "keep this file")
    @file.update_column(:storage_path, "../../#{File.basename(outside_path)}")

    result = TrashRetentionJob.perform_now

    assert_equal "failed", result.first[:status]
    assert @file.reload.deleted_at.present?
    assert_equal "keep this file", File.binread(outside_path)
  ensure
    File.delete(outside_path) if outside_path && File.exist?(outside_path)
  end

  test "overlapping cleanup is skipped when the database lock is held elsewhere" do
    job = TrashRetentionJob.new
    active_connection = ActiveRecord::Base.connection
    database_name = active_connection.select_value("SELECT DATABASE()")
    lock_name = job.send(:cleanup_lock_name_for_database, database_name)
    other_worker_database = job.send(:cleanup_lock_name_for_database, "#{database_name}_worker_2")
    assert_not_equal lock_name, other_worker_database
    assert_operator lock_name.length, :<=, 64

    config = ActiveRecord::Base.connection_db_config.configuration_hash
    lock_client = Mysql2::Client.new(
      host: config.fetch(:host),
      port: config.fetch(:port),
      username: config.fetch(:username),
      password: config.fetch(:password),
      database: config.fetch(:database)
    )
    quoted_lock_name = active_connection.quote(lock_name)
    acquired = lock_client.query("SELECT GET_LOCK(#{quoted_lock_name}, 0)").first.values.first
    assert_equal 1, acquired.to_i

    result = job.send(:with_cleanup_lock) { flunk "cleanup lock should prevent overlapping work" }

    assert_equal [], result
  ensure
    if lock_client
      lock_client.query("SELECT RELEASE_LOCK(#{quoted_lock_name})") if quoted_lock_name
      lock_client.close
    end
  end

  private

  def store_file(run, filename, contents)
    BackupStorage.for_run(run).store(StringIO.new(contents), backup_run: run, original_filename: filename)
  end
end

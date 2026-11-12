require "test_helper"

class DemoDataTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("demo_data_test")
    @storage = BackupStorage.new(root: @root)
    @demo = DemoData.new(storage: @storage)
  end

  teardown do
    FileUtils.remove_entry(@root)
  end

  test "create makes a demo account that can log in with the returned password" do
    result = @demo.create

    assert result.created
    assert_equal result.user, User.authenticate_by(username: "demo", password: result.password)
  end

  test "create uses the given password when there is one" do
    result = @demo.create(password: "presentation-day")

    assert_equal "presentation-day", result.password
    assert User.authenticate_by(username: "demo", password: "presentation-day")
  end

  test "create builds devices with completed and failed backup runs" do
    user = @demo.create.user

    assert_equal 3, user.devices.count
    runs = BackupRun.joins(:device).where(devices: { user_id: user.id })
    assert_equal 5, runs.completed.count
    assert_equal 1, runs.failed.count
    assert runs.all? { |run| run.created_at < Time.current }
  end

  test "every demo file is stored and passes the restore check" do
    user = @demo.create.user
    files = BackupFile.joins(backup_run: :device).where(devices: { user_id: user.id })

    assert_equal 8, files.count
    files.each { |file| assert_equal :ok, @storage.verify(file), "#{file.original_filename} failed verification" }
  end

  test "demo photos are real PNG images" do
    user = @demo.create.user
    photo = BackupFile.joins(backup_run: :device).where(devices: { user_id: user.id })
      .find_by(original_filename: "IMG_2041.png")

    assert File.binread(@storage.path_for(photo)).start_with?("\x89PNG\r\n\x1a\n".b)
  end

  test "create does nothing when the demo account already exists" do
    @demo.create

    assert_no_difference([ "User.count", "Device.count", "BackupFile.count" ]) do
      result = @demo.create
      assert_not result.created
      assert_nil result.password
    end
  end

  test "reset removes the demo account, its records, and its stored files" do
    user = @demo.create.user
    paths = BackupFile.joins(backup_run: :device).where(devices: { user_id: user.id }).map { |file| @storage.path_for(file) }

    assert @demo.reset

    assert_nil User.find_by(username: "demo")
    assert_equal 0, Device.where(user_id: user.id).count
    paths.each { |path| assert_not File.exist?(path) }
  end

  test "reset leaves other users alone" do
    @demo.create

    assert_no_difference("Device.where.not(user_id: nil).where(user: users(:alice)).count") do
      @demo.reset
    end
    assert User.exists?(users(:alice).id)
  end

  test "reset returns false when there is no demo account" do
    assert_not @demo.reset
  end
end

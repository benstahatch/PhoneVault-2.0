require "test_helper"
class BackupStorageTest < ActiveSupport::TestCase
  HELLO_SHA256 = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9".freeze
  EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".freeze

  setup do
    @root = Dir.mktmpdir("backup_storage_test")
    @storage = BackupStorage.new(root: @root)
    @run = BackupRun.create!(device: devices(:alice_phone), status: "running")
  end

  teardown do
    FileUtils.remove_entry(@root)
  end

  test "store saves the contents and records a matching SHA-256" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")

    assert file.persisted?
    assert_equal HELLO_SHA256, file.sha256
    assert_equal 11, file.size_bytes
    assert_equal "note.txt", file.original_filename
    assert_equal "hello world", File.binread(@storage.path_for(file))
  end

  test "store keeps readable paths relative and sanitizes uploaded filenames" do
    file = @storage.store(StringIO.new("x"), backup_run: @run, original_filename: "../../etc/passwd")

    assert_not file.storage_path.start_with?("/")
    assert_not_includes file.storage_path, ".."
    assert file.storage_path.start_with?("Alice-Pixel-Backups/")
  end

  test "store handles an empty file" do
    file = @storage.store(StringIO.new(""), backup_run: @run, original_filename: "empty.txt")

    assert_equal 0, file.size_bytes
    assert_equal EMPTY_SHA256, file.sha256
    assert_equal :ok, @storage.verify(file)
  end

  test "store hashes files larger than one chunk" do
    data = Random.bytes(BackupStorage::CHUNK_SIZE + 123)
    file = @storage.store(StringIO.new(data), backup_run: @run, original_filename: "photo.jpg")

    assert_equal Digest::SHA256.hexdigest(data), file.sha256
    assert_equal data.bytesize, file.size_bytes
  end

  test "store accepts a file exactly at the size limit" do
    storage = BackupStorage.new(root: @root, max_bytes: 11)
    file = storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")

    assert_equal 11, file.size_bytes
  end

  test "store rejects a file over the size limit and leaves nothing behind" do
    storage = BackupStorage.new(root: @root, max_bytes: 10)

    assert_raises(BackupStorage::TooLarge) do
      storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")
    end

    assert_equal 0, @run.backup_files.count
    assert_empty Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
  end

  test "store removes the partial file when a later chunk goes over the size limit" do
    # the first chunk fits and is written, the second one pushes it over
    storage = BackupStorage.new(root: @root, max_bytes: BackupStorage::CHUNK_SIZE + 10)
    data = Random.bytes(BackupStorage::CHUNK_SIZE + 123)

    assert_raises(BackupStorage::TooLarge) do
      storage.store(StringIO.new(data), backup_run: @run, original_filename: "photo.jpg")
    end

    assert_equal 0, @run.backup_files.count
    assert_empty Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
  end

  test "store removes the written file when the record can't be saved" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @storage.store(
        StringIO.new("hello world"),
        backup_run: @run,
        original_filename: ""
      )
    end

    assert_empty Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
  end


test "store does not overwrite an existing partial file" do
  # use a known UUID so the collision can be reproduced
  uuid = SecureRandom.uuid
  storage = BackupStorage.new(
    root: @root,
    uuid_generator: -> { uuid }
  )

  final_path = storage.root.join("Alice-Pixel-Backups", "note.txt")
  temp_path = final_path.dirname.join(".#{uuid}.partial")

  FileUtils.mkdir_p(final_path.dirname)
  File.binwrite(temp_path, "existing partial")

  # exclusive creation should reject the collision
  assert_raises(Errno::EEXIST) do
    storage.store(
      StringIO.new("new contents"),
      backup_run: @run,
      original_filename: "note.txt"
    )
  end

  # the existing file must remain untouched
  assert_equal "existing partial", File.binread(temp_path)
  assert_not final_path.exist?
end

  test "store preserves original filenames and numbers duplicates without overwriting" do
    first = @storage.store(StringIO.new("first"), backup_run: @run, original_filename: "note.txt")
    another_run = @run.device.backup_runs.create!(status: :running)
    second = @storage.store(StringIO.new("second"), backup_run: another_run, original_filename: "note.txt")
    assert_equal "Alice-Pixel-Backups/note.txt", first.storage_path
    assert_equal "Alice-Pixel-Backups/note (2).txt", second.storage_path
    assert_equal "first", File.binread(@storage.restore(first))
    assert_equal "second", File.binread(@storage.restore(second))
    assert_empty Dir.glob(File.join(@root, "**", ".*.partial"))
  end

  test "readable paths still reject traversal and symlink escapes" do
    [ "Benji-Backups/../outside.txt", "Benji-Backups/../../etc/passwd",
      "Benji-Backups/..", "Benji-Backups/a\\b", "Benji-Backups/" ].each do |path|
      file = BackupFile.new(backup_run: @run, storage_path: path)
      assert_raises(BackupStorage::Error) { @storage.path_for(file) }
    end
    Dir.mktmpdir("outside_readable") do |outside|
      File.write(File.join(outside, "secret.txt"), "secret")
      directory = @storage.root.join("Benji-Backups")
      directory.mkdir
      File.symlink(File.join(outside, "secret.txt"), directory.join("secret.txt"))
      file = BackupFile.new(backup_run: @run, storage_path: "Benji-Backups/secret.txt")
      assert_raises(BackupStorage::Error) { @storage.path_for(file) }
    end
  end

  test "device renames do not break existing backup paths" do
    first = @storage.store(StringIO.new("first"), backup_run: @run, original_filename: "photo.jpeg")
    @run.device.update!(name: "Benji")
    second = @storage.store(StringIO.new("second"), backup_run: @run, original_filename: "photo.jpeg")
    assert_equal "Benji-Backups/photo.jpeg", second.storage_path
    assert_equal "first", File.binread(@storage.restore(first))
  end

  test "legacy numeric folder and UUID paths still restore" do
    path = "#{@run.id}/#{SecureRandom.uuid}"
    FileUtils.mkdir_p(@storage.root.join(@run.id.to_s))
    File.binwrite(@storage.root.join(path), "hello world")
    file = @run.backup_files.create!(original_filename: "old.txt", storage_path: path,
      size_bytes: 11, sha256: HELLO_SHA256)
    assert_equal "hello world", File.binread(@storage.restore(file))
  end

  test "unsafe and long device names remain single bounded directory components" do
    @run.device.update!(name: "../" + "é" * 90)
    file = @storage.store(StringIO.new("data"), backup_run: @run, original_filename: "é" * 200 + ".txt")
    assert_equal 2, file.storage_path.split("/").size
    assert_not_includes file.storage_path, ".."
    assert_operator file.storage_path.bytesize, :<=, 255
    assert_equal :ok, @storage.verify(file)
  end

    test "store creates backup files with owner-only permissions" do
    # store a real backup file
    file = @storage.store(
      StringIO.new("hello world"),
      backup_run: @run,
      original_filename: "note.txt"
    )

    path = @storage.path_for(file)

    # only the file owner should have read and write access
    permissions = File.stat(path).mode & 0o777

    assert_equal 0o600, permissions
  end

  test "store rejects a backup run directory symlink outside the storage root" do
    # create a directory outside phonevault storage
    Dir.mktmpdir("phonevault_outside_run") do |outside_root|
      FileUtils.mkdir_p(@storage.root)

      run_directory = @storage.root.join("Alice-Pixel-Backups")

      # make the expected backup run directory point somewhere else
      File.symlink(outside_root, run_directory)

      # phonevault should never follow the symlink and write outside its root
      assert_raises(BackupStorage::Error) do
        @storage.store(
          StringIO.new("secret backup"),
          backup_run: @run,
          original_filename: "secret.txt"
        )
      end

      # nothing should have been written outside phonevault
      assert_empty Dir.children(outside_root)
    end
  end

  test "verify reports ok for an untouched file" do
    file = @storage.store(
      StringIO.new("hello world"),
      backup_run: @run,
      original_filename: "note.txt"
    )

    assert_equal :ok, @storage.verify(file)
  end

  test "verify reports corrupted when a single byte changes" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")
    File.binwrite(@storage.path_for(file), "hello World")

    assert_equal :corrupted, @storage.verify(file)
  end

    test "verify reports corrupted when the stored file size changes" do
    # store a valid file first
    file = @storage.store(
      StringIO.new("hello world"),
      backup_run: @run,
      original_filename: "note.txt"
    )

    # change the file size without updating the saved metadata
    File.binwrite(
      @storage.path_for(file),
      "different contents with a different size"
    )

    assert_equal :corrupted, @storage.verify(file)
  end

  test "verify reports missing when the file is gone" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")
    File.delete(@storage.path_for(file))

    assert_equal :missing, @storage.verify(file)
  end

  test "restore returns the path of a verified file" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")

    assert_equal "hello world", File.binread(@storage.restore(file))
  end

  test "restore raises for a missing file" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")
    File.delete(@storage.path_for(file))

    assert_raises(BackupStorage::MissingFile) { @storage.restore(file) }
  end

  test "restore raises for a corrupted file" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")
    File.binwrite(@storage.path_for(file), "tampered")

    assert_raises(BackupStorage::CorruptedFile) { @storage.restore(file) }
  end
test "path_for refuses paths that escape the storage root" do
  # reject relative traversal and absolute filesystem paths
  outside = BackupFile.new(storage_path: "../outside.txt")
  absolute = BackupFile.new(storage_path: "/etc/passwd")

  assert_raises(BackupStorage::Error) { @storage.path_for(outside) }
  assert_raises(BackupStorage::Error) { @storage.path_for(absolute) }
end

test "path_for rejects a storage path with the wrong backup run id" do
  # the path must belong to the same backup run as the record
  storage_path = "#{@run.id + 1}/#{SecureRandom.uuid}"

  backup_file = BackupFile.new(
    backup_run: @run,
    storage_path: storage_path
  )

  assert_raises(BackupStorage::Error) do
    @storage.path_for(backup_file)
  end
end

test "path_for rejects a storage path without a valid uuid" do
  # phonevault storage filenames should always use generated UUIDs
  backup_file = BackupFile.new(
    backup_run: @run,
    storage_path: "#{@run.id}/not-a-uuid"
  )

  assert_raises(BackupStorage::Error) do
    @storage.path_for(backup_file)
  end
end

test "path_for rejects a symlink that resolves outside the storage root" do
  # create a real file outside phonevault storage
  Dir.mktmpdir("phonevault_outside") do |outside_root|
    outside_file = Pathname(outside_root).join("secret.txt")
    File.write(outside_file, "outside phonevault")

    # create a valid-looking phonevault path that is actually a symlink
    uuid = SecureRandom.uuid
    storage_path = "#{@run.id}/#{uuid}"
    link_path = @storage.root.join(storage_path)

    FileUtils.mkdir_p(link_path.dirname)
    File.symlink(outside_file, link_path)

    backup_file = BackupFile.new(
      backup_run: @run,
      storage_path: storage_path
    )

    # reject the file because its real location escapes the backup root
    assert_raises(BackupStorage::Error) do
      @storage.path_for(backup_file)
    end
  end
end

  test "default_root uses PHONEVAULT_BACKUP_ROOT when configured" do
    Dir.mktmpdir("phonevault_backup_root") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root

      begin
        # use the configured storage directory when the environment variable exists
        assert_equal Pathname(root).expand_path, BackupStorage.default_root
      ensure
        # restore the environment after the test finishes
        if previous_root
          ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
        else
          ENV.delete("PHONEVAULT_BACKUP_ROOT")
        end
      end
    end
  end

  test "default_max_bytes is 10 GB when PHONEVAULT_MAX_UPLOAD_MB is not set" do
    with_max_upload_mb(nil) do
      assert_equal 10.gigabytes, BackupStorage.default_max_bytes
    end
  end

  test "default_max_bytes uses PHONEVAULT_MAX_UPLOAD_MB when configured" do
    with_max_upload_mb("500") do
      assert_equal 500.megabytes, BackupStorage.default_max_bytes
    end
  end

  test "default_max_bytes rejects a PHONEVAULT_MAX_UPLOAD_MB that isn't a positive whole number" do
    [ "abc", "0", "-5", "1.5" ].each do |value|
      with_max_upload_mb(value) do
        assert_raises(BackupStorage::Error, "expected #{value.inspect} to be rejected") do
          BackupStorage.default_max_bytes
        end
      end
    end
  end

  private

  # sets PHONEVAULT_MAX_UPLOAD_MB for the block, then restores the previous value
  def with_max_upload_mb(value)
    previous = ENV["PHONEVAULT_MAX_UPLOAD_MB"]
    ENV["PHONEVAULT_MAX_UPLOAD_MB"] = value
    yield
  ensure
    ENV["PHONEVAULT_MAX_UPLOAD_MB"] = previous
  end
end

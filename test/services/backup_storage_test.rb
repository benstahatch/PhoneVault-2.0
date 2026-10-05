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

  test "store keeps the path relative and ignores the uploaded filename" do
    file = @storage.store(StringIO.new("x"), backup_run: @run, original_filename: "../../etc/passwd")

    assert_not file.storage_path.start_with?("/")
    assert_not_includes file.storage_path, ".."
    assert file.storage_path.start_with?("#{@run.id}/")
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

  test "store removes the written file when the record can't be saved" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @storage.store(
        StringIO.new("hello world"),
        backup_run: @run,
        original_filename: ""
      )
    end

    assert_empty Dir.glob(File.join(@root, "**", "*")).select { |path| File.file?(path) }
  end


test "store does not overwrite an existing partial file" do
  # use a known UUID so the collision can be reproduced
  uuid = SecureRandom.uuid
  storage = BackupStorage.new(
    root: @root,
    uuid_generator: -> { uuid }
  )

  storage_path = File.join(@run.id.to_s, uuid)
  final_path = storage.root.join(storage_path)
  temp_path = Pathname("#{final_path}.partial")

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

  test "store does not overwrite an existing final file" do
    # use a known UUID so the final path can be reproduced
    uuid = SecureRandom.uuid
    storage = BackupStorage.new(
      root: @root,
      uuid_generator: -> { uuid }
    )

    storage_path = File.join(@run.id.to_s, uuid)
    final_path = storage.root.join(storage_path)
    temp_path = Pathname("#{final_path}.partial")

    FileUtils.mkdir_p(final_path.dirname)
    File.binwrite(final_path, "existing backup")

    # publishing the new file should fail instead of replacing the old one
    assert_raises(Errno::EEXIST) do
      storage.store(
        StringIO.new("new contents"),
        backup_run: @run,
        original_filename: "note.txt"
      )
    end

    # the existing completed backup must remain untouched
    assert_equal "existing backup", File.binread(final_path)

    # clean up only the temporary file created by this failed operation
    assert_not temp_path.exist?
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

      run_directory = @storage.root.join(@run.id.to_s)

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
end

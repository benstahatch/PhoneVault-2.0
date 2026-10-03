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
      @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "")
    end

    assert_empty Dir.glob(File.join(@root, "**", "*")).select { |path| File.file?(path) }
  end

  test "verify reports ok for an untouched file" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")

    assert_equal :ok, @storage.verify(file)
  end

  test "verify reports corrupted when a single byte changes" do
    file = @storage.store(StringIO.new("hello world"), backup_run: @run, original_filename: "note.txt")
    File.binwrite(@storage.path_for(file), "hello World")

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
    outside = BackupFile.new(storage_path: "../outside.txt")
    absolute = BackupFile.new(storage_path: "/etc/passwd")

    assert_raises(BackupStorage::Error) { @storage.path_for(outside) }
    assert_raises(BackupStorage::Error) { @storage.path_for(absolute) }
  end

  test "default_root uses PHONEVAULT_BACKUP_ROOT when configured" do
    Dir.mktmpdir("phonevault_backup_root") do |root|
      previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
      ENV["PHONEVAULT_BACKUP_ROOT"] = root

      begin
        assert_equal Pathname(root).expand_path, BackupStorage.default_root
      ensure
        if previous_root
          ENV["PHONEVAULT_BACKUP_ROOT"] = previous_root
        else
          ENV.delete("PHONEVAULT_BACKUP_ROOT")
        end
      end
    end
  end
end

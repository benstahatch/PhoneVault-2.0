require "test_helper"

class BackupDirectoryTest < ActiveSupport::TestCase
  setup do
    @temporary = Dir.mktmpdir("phonevault_paths")
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = @temporary
    @root = BackupDirectory.default_for(users(:alice))
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    FileUtils.remove_entry(@temporary)
  end

  test "each user's default folder is created under the backup root" do
    assert_equal Pathname(@temporary).realpath.join("users", users(:alice).id.to_s), @root
    assert @root.directory?
    assert_equal @root, BackupDirectory.resolve_or_default!("", users(:alice))
  end

  test "accepts directories containing spaces and cleans up write probes" do
    folder = @root.join("Family photos")
    folder.mkdir
    assert_equal folder, BackupDirectory.test_write!(folder.to_s)
    assert_empty folder.children
    assert_equal [ folder ], BackupDirectory.children(@root.to_s)
  end

  test "rejects relative paths traversal files and missing folders" do
    file = @root.join("file.txt")
    file.write("data")
    [ "relative", "#{@root}/../#{users(:bob).id}", file.to_s, "#{@root}/missing", "bad\0path" ].each do |path|
      assert_raises(BackupDirectory::Error, path) { BackupDirectory.resolve!(path) }
    end
  end

  test "folders outside the backup root are allowed and symlinks resolve to their real location" do
    Dir.mktmpdir("phonevault_external") do |external|
      directory = Pathname(external).realpath
      assert_equal directory, BackupDirectory.test_write!(external)
      link = @root.join("external-link")
      File.symlink(directory, link)
      assert_equal directory, BackupDirectory.resolve!(link.to_s)
      assert_empty BackupDirectory.children(@root.to_s), "symlinked folders are hidden from browsing"
    end
  end

  test "write failure produces an actionable error and leaves no probe" do
    # Directory mode alone is unreliable when tests run as root.
    original_create = Tempfile.method(:create)
    Tempfile.define_singleton_method(:create) { |*| raise Errno::EACCES }
    error = assert_raises(BackupDirectory::Error) { BackupDirectory.test_write!(@root.to_s) }
    assert_equal "Directory is not writable.", error.message
    assert_empty @root.children
  ensure
    Tempfile.define_singleton_method(:create, original_create)
  end
end

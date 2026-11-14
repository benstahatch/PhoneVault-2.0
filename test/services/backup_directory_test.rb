require "test_helper"

class BackupDirectoryTest < ActiveSupport::TestCase
  setup do
    @temporary = Dir.mktmpdir("phonevault_paths")
    @previous_root = ENV["PHONEVAULT_BACKUP_ROOT"]
    ENV["PHONEVAULT_BACKUP_ROOT"] = @temporary
    @browser = BackupDirectory.for_user(users(:alice))
  end

  teardown do
    @previous_root ? ENV["PHONEVAULT_BACKUP_ROOT"] = @previous_root : ENV.delete("PHONEVAULT_BACKUP_ROOT")
    FileUtils.remove_entry(@temporary)
  end

  test "accepts directories containing spaces and cleans up write probes" do
    folder = @browser.root.join("Family photos")
    folder.mkdir
    assert_equal folder, @browser.test_write!(folder.to_s)
    assert_empty folder.children
    assert_equal [ folder ], @browser.children(@browser.root.to_s)
  end

  test "rejects relative paths traversal sibling accounts files and missing folders" do
    other = BackupDirectory.for_user(users(:bob)).root
    file = @browser.root.join("file.txt")
    file.write("data")
    [ "relative", "#{@browser.root}/../#{users(:bob).id}", other.to_s,
      file.to_s, "#{@browser.root}/missing", "#{@browser.root}other", "bad\0path" ].each do |path|
      assert_raises(BackupDirectory::Error, path) { @browser.resolve!(path) }
    end
  end

  test "rejects symlink folders and hides them from browsing" do
    other = BackupDirectory.for_user(users(:bob)).root
    link = @browser.root.join("escape")
    File.symlink(other, link)
    assert_raises(BackupDirectory::Error) { @browser.resolve!(link.to_s) }
    assert_empty @browser.children(@browser.root.to_s)
  end

  test "refuses a symlink at the account root" do
    root = @browser.root
    root.rmdir
    File.symlink(@temporary, root)
    assert_raises(BackupDirectory::Error) { BackupDirectory.for_user(users(:alice)) }
  end

  test "write failure produces an actionable error and leaves no probe" do
    # Directory mode alone is unreliable when tests run as root.
    original_create = Tempfile.method(:create)
    Tempfile.define_singleton_method(:create) { |*| raise Errno::EACCES }
    error = assert_raises(BackupDirectory::Error) { @browser.test_write!(@browser.root.to_s) }
    assert_equal "Directory is not writable.", error.message
    assert_empty @browser.root.children
  ensure
    Tempfile.define_singleton_method(:create, original_create)
  end
end

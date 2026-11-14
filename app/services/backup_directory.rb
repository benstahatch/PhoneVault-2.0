require "fileutils"
require "tempfile"

# Browser paths are server paths. Each account gets a private directory under
# the configured root; existing backups at the root remain restorable.
class BackupDirectory
  class Error < StandardError; end

  attr_reader :root

  def self.for_user(user)
    base = BackupStorage.default_root
    FileUtils.mkdir_p(base, mode: 0o700)
    base = base.realpath
    directory = base
    [ "users", user.id.to_s ].each do |part|
      directory = directory.join(part)
      raise Error, "Storage directories cannot be symbolic links." if directory.symlink?
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise Error, "Storage directories cannot be symbolic links." if directory.symlink?
      raise Error, "Invalid storage directory." unless directory.realpath.parent == directory.parent.realpath
    end
    new(root: directory)
  rescue SystemCallError
    raise Error, "Backup storage is unavailable. Check the server storage configuration and permissions."
  end

  def initialize(root:)
    @root = Pathname(root).realpath
  rescue SystemCallError
    raise Error, "Backup storage is unavailable."
  end

  def resolve!(input)
    path = Pathname(input.to_s)
    unless path.absolute? && !path.each_filename.any? { |part| part == ".." }
      raise Error, "Enter an absolute Linux path without parent-directory traversal."
    end
    path = path.cleanpath
    unless path == root || path.to_s.start_with?("#{root}/")
      raise Error, "Choose a folder inside your backup storage."
    end

    # Reject all symlink components, including links into another account.
    cursor = root
    path.relative_path_from(root).each_filename do |part|
      next if part == "."
      cursor = cursor.join(part)
      raise Error, "Symbolic links cannot be used as save folders." if cursor.symlink?
    end
    resolved = path.realpath
    unless resolved == root || resolved.to_s.start_with?("#{root}/")
      raise Error, "Choose a folder inside your backup storage."
    end
    raise Error, "Choose a directory." unless resolved.directory?
    resolved
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise Error, "Directory does not exist."
  rescue Errno::EACCES
    raise Error, "Directory is not accessible."
  rescue ArgumentError
    raise Error, "Invalid directory path."
  end

  def test_write!(input)
    directory = resolve!(input)
    Tempfile.create([ ".phonevault-write-test-", ".tmp" ], directory.to_s) do |file|
      file.write("PhoneVault write test")
      file.flush
      file.fsync
    end
    directory
  rescue Errno::EACCES, Errno::EROFS
    raise Error, "Directory is not writable."
  rescue Errno::ENOSPC
    raise Error, "The storage device is full."
  rescue SystemCallError
    raise Error, "Unable to write to this directory. Check server storage permissions."
  end

  def children(input)
    directory = resolve!(input)
    directory.children.select { |child| !child.symlink? && child.directory? }
      .sort_by { |child| child.basename.to_s.downcase }
  rescue SystemCallError
    raise Error, "Directory cannot be listed. Check server storage permissions."
  end
end

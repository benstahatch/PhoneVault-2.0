require "fileutils"
require "tempfile"

# Checks save folders on the server. Any existing directory the app can write to
# may be chosen; paths are resolved to their real location (no symlinks) before saving.
module BackupDirectory
  class Error < StandardError; end

  module_function

  # the pre-filled save folder for a user's uploads: <backup root>/users/<id>
  def default_for(user)
    path = BackupStorage.default_root.join("users", user.id.to_s)
    FileUtils.mkdir_p(path, mode: 0o700)
    resolve!(path)
  rescue SystemCallError
    raise Error, "Backup storage is unavailable. Check the server storage configuration and permissions."
  end

  # the folder the user picked, or their default folder when they haven't picked one
  def resolve_or_default!(input, user)
    input.present? ? resolve!(input) : default_for(user)
  end

  def resolve!(input)
    path = Pathname(input.to_s)
    unless path.absolute? && path.each_filename.none?("..")
      raise Error, "Enter an absolute Linux path without parent-directory traversal."
    end

    resolved = path.realpath
    raise Error, "Choose a directory." unless resolved.directory?
    resolved
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise Error, "Directory does not exist."
  rescue Errno::EACCES
    raise Error, "Directory is not accessible."
  rescue Errno::ELOOP
    raise Error, "Directory contains a symbolic-link loop."
  rescue Errno::ENAMETOOLONG
    raise Error, "Directory path is too long."
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

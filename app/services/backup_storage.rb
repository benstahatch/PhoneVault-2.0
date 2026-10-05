require "digest"
require "fileutils"
require "securerandom"

# Writes backup file contents to disk, records their metadata, and checks
# them against their SHA-256 on the way back out.
#
# storage_path is saved relative to the root and follows the format
# backup_run_id/uuid. The uploaded filename only ever lives in the database,
# so a name like "../../etc/passwd" can't choose where a file is written.
class BackupStorage
  class Error < StandardError; end
  class MissingFile < Error; end
  class CorruptedFile < Error; end

  CHUNK_SIZE = 1.megabyte

  # valid UUID format used for generated storage filenames
  UUID_PATTERN =
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def self.default_root
    configured_root = ENV["PHONEVAULT_BACKUP_ROOT"]

    return Pathname(configured_root).expand_path if configured_root.present?

    base =
      if Rails.env.test?
        Rails.root.join("tmp", "storage")
      else
        Rails.root.join("storage")
      end

    base.join("backups")
  end

  attr_reader :root

  def initialize(root: self.class.default_root, uuid_generator: SecureRandom.method(:uuid))
    @root = Pathname(root).expand_path
    @uuid_generator = uuid_generator
  end

  # Streams io to disk while hashing it, then creates the BackupFile row.
  # The data goes to a .partial file first and is published only once complete,
  # so a crash mid-write never leaves a file that looks finished.
  def store(io, backup_run:, original_filename:)
    uuid = @uuid_generator.call

    # only allow the UUID format phonevault generates for stored files
    unless uuid.match?(UUID_PATTERN)
      raise Error, "invalid generated storage filename"
    end

    # verify the backup run directory before writing anything to disk
    run_directory = secure_run_directory(backup_run)

    storage_path = File.join(backup_run.id.to_s, uuid)
    final_path = run_directory.join(uuid)
    temp_path = Pathname("#{final_path}.partial")

    temp_created = false
    final_created = false

    digest = Digest::SHA256.new
    size = 0

    # create the temporary file without overwriting an existing path
    File.open(temp_path, "wbx", 0o600) do |file|
      temp_created = true

      while (chunk = io.read(CHUNK_SIZE))
        digest << chunk
        size += chunk.bytesize
        file.write(chunk)
      end

      file.fsync
    end

    # publish the completed file without overwriting an existing destination
    File.link(temp_path, final_path)
    final_created = true

    File.unlink(temp_path)
    temp_created = false

    backup_run.backup_files.create!(
      original_filename: original_filename,
      storage_path: storage_path,
      size_bytes: size,
      sha256: digest.hexdigest
    )
  rescue StandardError
    # only remove files that this store operation actually created
    FileUtils.rm_f(temp_path) if temp_created
    FileUtils.rm_f(final_path) if final_created
    raise
  end

  # Returns :ok, :missing, or :corrupted.
  def verify(backup_file)
    path = path_for(backup_file)
    return :missing unless path.file?

    # reject a changed file size before doing the more expensive hash check
    return :corrupted unless path.size == backup_file.size_bytes

    Digest::SHA256.file(path).hexdigest.casecmp?(backup_file.sha256) ? :ok : :corrupted
  end

  # Returns the path of a file that has just passed verification, or raises.
  def restore(backup_file)
    case verify(backup_file)
    when :missing
      raise MissingFile, "backup file #{backup_file.id} is missing from storage"
    when :corrupted
      raise CorruptedFile, "backup file #{backup_file.id} failed integrity verification"
    end

    path_for(backup_file)
  end

  # validates the stored path and makes sure it stays inside the backup root
  def path_for(backup_file)
    storage_path = backup_file.storage_path.to_s
    parts = storage_path.split("/", -1)

    valid_storage_path =
      parts.length == 2 &&
      parts.first == backup_file.backup_run_id.to_s &&
      parts.last.match?(UUID_PATTERN)

    unless valid_storage_path
      raise Error, "invalid storage path for backup file #{backup_file.id}"
    end

    path = root.join(storage_path).expand_path

    # reject normal path traversal before touching the filesystem
    unless path.to_s.start_with?("#{root}#{File::SEPARATOR}")
      raise Error, "storage path for backup file #{backup_file.id} is outside the storage root"
    end

    # missing files are handled later by verify
    return path unless path.exist?

    real_root = root.realpath
    real_path = path.realpath

    # reject sym[118;1:3ulinks that resolve outside the real backup directory
    unless real_path.to_s.start_with?("#{real_root}#{File::SEPARATOR}")
      raise Error, "resolved storage path for backup file #{backup_file.id} is outside the storage root"
    end

    real_path
  end

  private

  # creates the backup run directory and rejects symlinks outside storage
  def secure_run_directory(backup_run)
    FileUtils.mkdir_p(root, mode: 0o700)
    real_root = root.realpath

    run_directory = root.join(backup_run.id.to_s)

    # never trust an existing symlink as a backup directory
    if run_directory.symlink?
      raise Error, "backup run directory #{backup_run.id} cannot be a symlink"
    end

    FileUtils.mkdir_p(run_directory, mode: 0o700)

    # check again after creation before any backup bytes are written
    if run_directory.symlink?
      raise Error, "backup run directory #{backup_run.id} cannot be a symlink"
    end

    real_run_directory = run_directory.realpath

    unless real_run_directory.parent == real_root
      raise Error, "backup run directory #{backup_run.id} is outside the storage root"
    end

    run_directory
  end
end

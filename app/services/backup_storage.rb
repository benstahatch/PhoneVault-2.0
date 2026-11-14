require "digest"
require "fileutils"
require "securerandom"

# Writes backup file contents to disk, records their metadata, and checks
# them against their SHA-256 on the way back out.
#
# New paths use Device-Backups/original-filename with safe path components.
# Existing run_id/UUID paths remain readable. Atomic publication never replaces
# an existing file; repeated names receive a numbered suffix.
class BackupStorage
  class Error < StandardError; end
  class MissingFile < Error; end
  class CorruptedFile < Error; end
  class TooLarge < Error; end

  CHUNK_SIZE = 1.megabyte
  DEFAULT_MAX_BYTES = 10.gigabytes

  # valid UUID format used for generated storage filenames
  UUID_PATTERN =
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def self.for_run(run)
    if run.storage_root.present?
      return new(root: BackupDirectory.server.resolve!(run.storage_root))
    end

    return new if run.backup_subdirectory.blank?

    # Saved relative to the global root so remounting storage preserves paths.
    directory = BackupDirectory.for_user(run.device.user)
    path = directory.resolve!(default_root.realpath.join(run.backup_subdirectory).to_s)
    new(root: path)
  end

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

  # PHONEVAULT_MAX_UPLOAD_MB sets the limit in megabytes; a bad value fails
  # loudly instead of quietly allowing uploads of any size
  def self.default_max_bytes
    configured_mb = ENV["PHONEVAULT_MAX_UPLOAD_MB"]

    return DEFAULT_MAX_BYTES if configured_mb.blank?

    megabytes = Integer(configured_mb, exception: false)

    unless megabytes&.positive?
      raise Error, "PHONEVAULT_MAX_UPLOAD_MB must be a positive whole number of megabytes"
    end

    megabytes.megabytes
  end

  attr_reader :root, :max_bytes

  def initialize(root: self.class.default_root, max_bytes: self.class.default_max_bytes, uuid_generator: SecureRandom.method(:uuid))
    @root = Pathname(root).expand_path
    @max_bytes = max_bytes
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
    folder = "#{safe_component(backup_run.device.name, limit: 80).gsub(/\s+/, "-")}-Backups"
    run_directory = secure_directory(folder)
    filename = safe_component(original_filename, limit: 140)
    temp_path = run_directory.join(".#{uuid}.partial")

    temp_created = false
    final_created = false

    digest = Digest::SHA256.new
    size = 0

    # create the temporary file without overwriting an existing path
    File.open(temp_path, "wbx", 0o600) do |file|
      temp_created = true

      while (chunk = io.read(CHUNK_SIZE))
        size += chunk.bytesize

        # stop before writing the chunk that goes over the limit
        if size > max_bytes
          raise TooLarge, "upload is larger than the #{max_bytes} byte limit"
        end

        digest << chunk
        file.write(chunk)
      end

      file.fsync
    end

    # publish the completed file without overwriting an existing destination
    final_path = publish_without_overwriting(temp_path, run_directory, filename)
    final_created = true
    storage_path = File.join(folder, final_path.basename.to_s)

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

    legacy_path = parts.length == 2 &&
      parts.first == backup_file.backup_run_id.to_s && parts.last.match?(UUID_PATTERN)
    readable_path = parts.length == 2 && parts.first.end_with?("-Backups") &&
      parts.all? { |part| safe_path_component?(part) }
    valid_storage_path = legacy_path || readable_path

    unless valid_storage_path
      raise Error, "invalid storage path for backup file #{backup_file.id}"
    end

    path = root.join(storage_path).expand_path

    # reject normal path traversal before touching the filesystem
    unless root == Pathname("/") || path.to_s.start_with?("#{root}#{File::SEPARATOR}")
      raise Error, "storage path for backup file #{backup_file.id} is outside the storage root"
    end

    # missing files are handled later by verify
    return path unless path.exist?

    real_root = root.realpath
    real_path = path.realpath

    # reject symlinks that resolve outside the real backup directory
    unless real_root == Pathname("/") || real_path.to_s.start_with?("#{real_root}#{File::SEPARATOR}")
      raise Error, "resolved storage path for backup file #{backup_file.id} is outside the storage root"
    end

    real_path
  end

  private

  def safe_component(value, limit:)
    name = ActiveStorage::Filename.new(value.to_s).sanitized
      .gsub(/[[:cntrl:]]/, "_").gsub("..", "_")
    name = name.byteslice(0, limit).to_s.scrub("").strip
    name = "file" if name.blank? || name == "."
    name
  end

  def safe_path_component?(part)
    part.present? && part != "." && !part.include?("..") &&
      !part.match?(/[\\\/[:cntrl:]]/)
  end

  def publish_without_overwriting(temp_path, directory, filename)
    extension = File.extname(filename)
    stem = filename.delete_suffix(extension)
    10_000.times do |index|
      name = index.zero? ? filename : "#{stem} (#{index + 1})#{extension}"
      destination = directory.join(name)
      begin
        File.link(temp_path, destination)
        return destination
      rescue Errno::EEXIST
        # Atomic link protects existing files, including concurrent uploads.
      end
    end
    raise Error, "Too many backups with this filename in the selected folder"
  end

  # Only a direct child of the selected root can be used as a device folder.
  def secure_directory(folder)
    FileUtils.mkdir_p(root, mode: 0o700)
    real_root = root.realpath
    directory = real_root.join(folder)
    raise Error, "Backup directory cannot be a symlink" if directory.symlink?
    FileUtils.mkdir_p(directory, mode: 0o700)
    raise Error, "Backup directory cannot be a symlink" if directory.symlink?
    unless directory.realpath.parent == real_root
      raise Error, "Backup directory is outside the storage root"
    end
    directory
  end
end

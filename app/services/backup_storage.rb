require "digest"
require "fileutils"
require "securerandom"

# Writes backup file contents to disk, records their metadata, and checks
# them against their SHA-256 on the way back out.
#
# storage_path is saved relative to the root, and the file on disk is named
# with a random UUID. The uploaded filename only ever lives in the database,
# so a name like "../../etc/passwd" can't choose where a file is written.
class BackupStorage
  class Error < StandardError; end
  class MissingFile < Error; end
  class CorruptedFile < Error; end

  CHUNK_SIZE = 1.megabyte

def self.default_root
  Pathname(
    ENV.fetch(
      "PHONEVAULT_BACKUP_ROOT",
      Rails.root.join("storage", "backups").to_s
    )
  )
end
  attr_reader :root

  def initialize(root: self.class.default_root)
    @root = Pathname(root).expand_path
  end

  # Streams io to disk while hashing it, then creates the BackupFile row.
  # The data goes to a .partial file first and is renamed once complete,
  # so a crash mid-write never leaves a file that looks finished.
  def store(io, backup_run:, original_filename:)
    storage_path = File.join(backup_run.id.to_s, SecureRandom.uuid)
    final_path = root.join(storage_path)
    temp_path = Pathname("#{final_path}.partial")
    FileUtils.mkdir_p(final_path.dirname)

    digest = Digest::SHA256.new
    size = 0
    File.open(temp_path, "wb") do |file|
      while (chunk = io.read(CHUNK_SIZE))
        digest << chunk
        size += chunk.bytesize
        file.write(chunk)
      end
      file.fsync
    end
    File.rename(temp_path, final_path)

    backup_run.backup_files.create!(
      original_filename: original_filename,
      storage_path: storage_path,
      size_bytes: size,
      sha256: digest.hexdigest
    )
  rescue StandardError
    # Don't leave orphaned bytes behind if the write or the insert failed.
    FileUtils.rm_f([ temp_path, final_path ].compact)
    raise
  end

  # Returns :ok, :missing, or :corrupted.
  def verify(backup_file)
    path = path_for(backup_file)
    return :missing unless path.file?

    Digest::SHA256.file(path).hexdigest.casecmp?(backup_file.sha256) ? :ok : :corrupted
  end

  # Returns the path of a file that has just passed verification, or raises.
  def restore(backup_file)
    case verify(backup_file)
    when :missing then raise MissingFile, "backup file #{backup_file.id} is missing from storage"
    when :corrupted then raise CorruptedFile, "backup file #{backup_file.id} does not match its SHA-256"
    end

    path_for(backup_file)
  end

  def path_for(backup_file)
    path = root.join(backup_file.storage_path).expand_path
    unless path.to_s.start_with?("#{root}/")
      raise Error, "storage path for backup file #{backup_file.id} is outside the storage root"
    end

    path
  end
end

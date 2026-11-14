# Works out what preview a stored backup file can safely have in the history:
# a thumbnail for real images, the first lines for text files, or nothing.
#
# Images are recognized by their first bytes, never by the filename, so an
# HTML or SVG file renamed to "photo.png" is never shown in the browser.
class BackupPreview
  IMAGE_SIGNATURES = {
    "image/png" => "\x89PNG\r\n\x1a\n".b,
    "image/jpeg" => "\xFF\xD8\xFF".b,
    "image/gif" => "GIF8".b
  }.freeze

  TEXT_EXTENSIONS = %w[txt csv md log vcf ics json].freeze

  # larger photos still restore fine, they just don't get a thumbnail
  MAX_IMAGE_BYTES = 25.megabytes
  TEXT_BYTES = 2.kilobytes
  TEXT_LINES = 6

  Excerpt = Struct.new(:text, :truncated, keyword_init: true)

  def initialize(storage: BackupStorage.new)
    @storage = storage
  end

  # returns the image's content type, or nil when it isn't a previewable image
  def image_type(backup_file)
    return nil if backup_file.size_bytes.to_i > MAX_IMAGE_BYTES

    header = read_start(backup_file, 12)
    return nil unless header
    return "image/webp" if header.start_with?("RIFF".b) && header.byteslice(8, 4) == "WEBP".b

    IMAGE_SIGNATURES.find { |_type, signature| header.start_with?(signature) }&.first
  end

  # returns the first few lines of a text file, or nil for anything else
  def text_excerpt(backup_file)
    return nil unless TEXT_EXTENSIONS.include?(extension(backup_file))

    data = read_start(backup_file, TEXT_BYTES)
    # a NUL byte means it's really a binary file with a text-looking name
    return nil if data.nil? || data.include?("\0")

    # scrub drops a multi-byte character cut in half at the end of the read
    lines = data.force_encoding(Encoding::UTF_8).scrub("").lines
    Excerpt.new(
      text: lines.first(TEXT_LINES).join.rstrip,
      truncated: lines.size > TEXT_LINES || backup_file.size_bytes.to_i > TEXT_BYTES
    )
  end

  # a short label like "PDF" for files with no thumbnail or text
  def badge(backup_file)
    extension(backup_file).first(4).upcase.presence || "FILE"
  end

  private

  def extension(backup_file)
    File.extname(backup_file.original_filename.to_s).delete_prefix(".").downcase
  end

  # reads the start of the stored file; nil when it is missing or its path is unsafe
  def read_start(backup_file, bytes)
    path = @storage.path_for(backup_file)
    return nil unless path.file?

    File.open(path, "rb") { |file| file.read(bytes) || "".b }
  rescue BackupStorage::Error, SystemCallError
    nil
  end
end

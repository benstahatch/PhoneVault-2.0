require "test_helper"

class BackupPreviewTest < ActiveSupport::TestCase
  PNG_BYTES = "\x89PNG\r\n\x1a\n".b + ("x" * 20)

  setup do
    @root = Dir.mktmpdir("backup_preview_test")
    @storage = BackupStorage.new(root: @root)
    @preview = BackupPreview.new(storage: @storage)
    @run = devices(:alice_phone).backup_runs.create!(status: :completed)
  end

  teardown do
    FileUtils.remove_entry(@root)
  end

  test "recognizes PNG, JPEG, GIF, and WebP images by their bytes" do
    {
      PNG_BYTES => "image/png",
      "\xFF\xD8\xFF\xE0rest".b => "image/jpeg",
      "GIF89a-rest" => "image/gif",
      "RIFF\x00\x00\x00\x00WEBPVP8 ".b => "image/webp"
    }.each do |bytes, type|
      assert_equal type, @preview.image_type(store(bytes, "picture.bin"))
    end
  end

  test "an HTML or SVG file named like a photo is not treated as an image" do
    assert_nil @preview.image_type(store("<html><script>alert(1)</script></html>", "photo.png"))
    assert_nil @preview.image_type(store("<svg xmlns='http://www.w3.org/2000/svg'></svg>", "photo.svg"))
  end

  test "images over the size limit get no thumbnail" do
    file = store(PNG_BYTES, "huge.png")
    file.size_bytes = BackupPreview::MAX_IMAGE_BYTES + 1

    assert_nil @preview.image_type(file)
  end

  test "text excerpt shows the first lines and says when there is more" do
    excerpt = @preview.text_excerpt(store((1..10).map { |n| "line #{n}" }.join("\n"), "notes.txt"))

    assert_equal (1..6).map { |n| "line #{n}" }.join("\n"), excerpt.text
    assert excerpt.truncated
  end

  test "a short text file is shown whole" do
    excerpt = @preview.text_excerpt(store("month,amount\nMay,10\n", "budget.CSV"))

    assert_equal "month,amount\nMay,10", excerpt.text
    assert_not excerpt.truncated
  end

  test "no text excerpt for other extensions or binary content" do
    assert_nil @preview.text_excerpt(store("plain words", "report.pdf"))
    assert_nil @preview.text_excerpt(store("abc\0def", "fake.txt"))
  end

  test "a missing stored file gives no preview instead of an error" do
    file = store(PNG_BYTES, "gone.png")
    File.delete(@storage.path_for(file))

    assert_nil @preview.image_type(file)
    assert_nil @preview.text_excerpt(file)
  end

  test "badge shows the extension, or FILE when there is none" do
    assert_equal "PDF", @preview.badge(store("x", "scan.pdf"))
    assert_equal "FILE", @preview.badge(store("x", "README"))
  end

  private

  def store(bytes, filename)
    @storage.store(StringIO.new(bytes), backup_run: @run, original_filename: filename)
  end
end

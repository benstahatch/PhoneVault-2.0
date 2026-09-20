require "test_helper"

class BackupFileTest < ActiveSupport::TestCase
  test "sha256 must be present" do
    file = BackupFile.new
    file.valid?
    assert file.errors[:sha256].any?, "expected an error on sha256"
  end

  test "sha256 must be 64 characters" do
    file = BackupFile.new(sha256: "abc123")
    file.valid?
    assert file.errors[:sha256].any?
  end

  test "sha256 must be hexadecimal" do
    file = BackupFile.new(sha256: "z" * 64)
    file.valid?
    assert file.errors[:sha256].any?
  end

  test "a well-formed sha256 is accepted" do
    file = BackupFile.new(sha256: "a" * 64)
    file.valid?
    assert_empty file.errors[:sha256]
  end

  test "size_bytes cannot be negative" do
    file = BackupFile.new(size_bytes: -1)
    file.valid?
    assert file.errors[:size_bytes].any?
  end
end

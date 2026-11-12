require "securerandom"
require "stringio"
require "zlib"

# Creates a "demo" account with devices and a realistic backup history for
# presentations. Files go through BackupStorage like real uploads, so their
# hashes are real and Restore works on them.
#
# This is deliberately NOT in db/seeds.rb: seeds run automatically when a new
# production database is created, and every install would get a demo login.
class DemoData
  USERNAME = "demo".freeze

  Result = Struct.new(:user, :password, :created, keyword_init: true)

  # each device gets backups on these many days ago; a nil file list makes a failed run
  DEVICES = [
    { name: "Jordan's iPhone", device_type: "phone", runs: [
      { days_ago: 21, files: [ [ "IMG_2041.png", :photo, [ 230, 107, 0 ] ], [ "contacts.vcf", :contacts ] ] },
      { days_ago: 9, files: [ [ "IMG_2108.png", :photo, [ 37, 99, 235 ] ], [ "calendar.ics", :calendar ] ] },
      { days_ago: 2, files: [ [ "IMG_2177.png", :photo, [ 22, 163, 74 ] ] ] }
    ] },
    { name: "Work Laptop", device_type: "laptop", runs: [
      { days_ago: 14, files: [ [ "notes.txt", :notes ], [ "budget-2026.csv", :csv ] ] },
      { days_ago: 5, files: nil },
      { days_ago: 1, files: [ [ "notes.txt", :notes ] ] }
    ] },
    { name: "Living Room Tablet", device_type: "tablet", runs: [] }
  ].freeze

  def initialize(storage: BackupStorage.new)
    @storage = storage
  end

  def create(password: nil)
    existing = User.find_by(username: USERNAME)
    return Result.new(user: existing, password: nil, created: false) if existing

    password = password.presence || SecureRandom.alphanumeric(12)

    ActiveRecord::Base.transaction do
      user = User.create!(username: USERNAME, display_name: "Demo User", password: password)
      DEVICES.each { |spec| create_device(user, spec) }
      Result.new(user: user, password: password, created: true)
    end
  end

  # removes the demo account, its records, and its stored files; returns true if there was one
  def reset
    user = User.find_by(username: USERNAME)
    return false unless user

    ActiveRecord::Base.transaction do
      user.devices.each do |device|
        device.backup_runs.each do |run|
          run.backup_files.each do |file|
            FileUtils.rm_f(@storage.root.join(file.storage_path))
            file.destroy!
          end
          FileUtils.rm_rf(@storage.root.join(run.id.to_s))
          run.reload.destroy!
        end
        device.reload.destroy!
      end
      user.reload.destroy!
    end
    true
  end

  private

  def create_device(user, spec)
    device = user.devices.create!(name: spec[:name], device_type: spec[:device_type])
    spec[:runs].each { |run_spec| create_run(device, run_spec) }
  end

  def create_run(device, run_spec)
    started = run_spec[:days_ago].days.ago.change(hour: 21, min: 30)
    run = device.backup_runs.create!(status: :running, created_at: started, started_at: started)

    if run_spec[:files].nil?
      run.update!(status: :failed, completed_at: started + 2.minutes)
      return
    end

    run_spec[:files].each do |filename, kind, color|
      @storage.store(StringIO.new(file_contents(kind, color)), backup_run: run, original_filename: filename)
    end
    run.update!(status: :completed, completed_at: started + 3.minutes)
  end

  def file_contents(kind, color)
    case kind
    when :photo then solid_png(color)
    when :contacts
      "BEGIN:VCARD\nVERSION:3.0\nFN:Alex Rivera\nTEL:+1-555-0142\nEND:VCARD\n" \
        "BEGIN:VCARD\nVERSION:3.0\nFN:Sam Lee\nTEL:+1-555-0187\nEND:VCARD\n"
    when :calendar
      "BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nSUMMARY:Class presentation\n" \
        "DTSTART:20261118T150000Z\nEND:VEVENT\nEND:VCALENDAR\n"
    when :notes then "Things to back up:\n- photos\n- contacts\n- calendar\n"
    when :csv then "month,amount\nSeptember,120\nOctober,95\nNovember,110\n"
    end
  end

  # a small single-color PNG so restored "photos" open in any image viewer
  def solid_png(rgb, size: 64)
    row = [ 0, *rgb * size ].pack("C*")
    image_data = Zlib::Deflate.deflate(row * size)
    header = [ size, size, 8, 2, 0, 0, 0 ].pack("NNCCCCC")

    "\x89PNG\r\n\x1a\n".b + png_chunk("IHDR", header) + png_chunk("IDAT", image_data) + png_chunk("IEND", "")
  end

  def png_chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end

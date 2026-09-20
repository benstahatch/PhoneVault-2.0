=begin
run this by copy/pasting
bin/rails runner '

For example:

bin/rails runner ' <---
require "digest"
...............
=end
require "digest"
require "securerandom"

ActiveRecord::Base.transaction do
  username = "pv_test_#{SecureRandom.hex(4)}"

  user = User.create!(
    username: username,
    display_name: "PhoneVault Test User",
    password: "TestPassword123!",
    password_confirmation: "TestPassword123!"
  )

  device = user.devices.create!(
    name: "Test MacBook",
    device_type: :laptop
  )

  backup_run = device.backup_runs.create!(
    status: :completed,
    started_at: 1.minute.ago,
    completed_at: Time.current
  )

  backup_file = backup_run.backup_files.create!(
    original_filename: "hello.txt",
    storage_path: "test/hello.txt",
    size_bytes: 5,
    sha256: Digest::SHA256.hexdigest("hello")
  )

  security_event = user.security_events.create!(
    event_type: "BACKUP_SUCCESS",
    ip_address: "127.0.0.1"
  )

  puts "USER:           #{user.username}"
  puts "DEVICE:         #{user.devices.first.name}"
  puts "BACKUP STATUS:  #{device.backup_runs.first.status}"
  puts "FILE:           #{backup_run.backup_files.first.original_filename}"
  puts "SHA-256:        #{backup_file.sha256}"
  puts "SECURITY EVENT: #{security_event.event_type}"

  raise ActiveRecord::Rollback
end

puts
puts "Test transaction rolled back successfully."

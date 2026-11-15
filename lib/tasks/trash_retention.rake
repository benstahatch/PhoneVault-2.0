namespace :phonevault do
  namespace :trash do
    desc "Preview or clean up trashed backups past their configured retention period"
    task cleanup: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))

      if !dry_run && !TrashRetention.cleanup_enabled?
        puts "Trash retention cleanup is disabled. Set PHONEVAULT_TRASH_CLEANUP_ENABLED=true to delete expired backups."
        next
      end

      results = TrashRetentionJob.perform_now(dry_run: dry_run)
      puts(dry_run ? "Trash retention dry run:" : "Trash retention cleanup:")

      results.each do |item|
        summary = "#{item[:status]}: #{item[:owner]}/#{item[:device]}/#{item[:filename]} " \
          "(#{item[:size_bytes]} bytes; trashed #{item[:deleted_at]})"
        puts(item[:error].present? ? "#{summary} — #{item[:error]}" : summary)
      end

      puts "No expired trashed backups found." if results.empty?
    end
  end
end

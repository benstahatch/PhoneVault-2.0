# Environment-backed settings for automatic removal of expired Trash entries.
class TrashRetention
  RETENTION_DAYS = [ 7, 30, 60, 90 ].freeze
  DEFAULT_DAYS = 30

  class ConfigurationError < StandardError; end

  def self.retention_days
    value = Integer(ENV.fetch("PHONEVAULT_TRASH_RETENTION_DAYS", DEFAULT_DAYS.to_s), exception: false)
    return value if RETENTION_DAYS.include?(value)

    raise ConfigurationError, "PHONEVAULT_TRASH_RETENTION_DAYS must be one of #{RETENTION_DAYS.join(', ')}"
  end

  def self.cleanup_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("PHONEVAULT_TRASH_CLEANUP_ENABLED", "false"))
  end
end

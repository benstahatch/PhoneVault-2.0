module TimeHelper
  # <time datetime="2026-11-15T21:30:00Z">Nov 15, 2026 21:30 UTC</time>
  def timestamp(time, format: "%b %d, %Y %H:%M %Z", **options)
    tag.time(time.strftime(format), datetime: time.iso8601, **options)
  end
end

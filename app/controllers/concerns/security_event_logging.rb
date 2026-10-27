module SecurityEventLogging
  extend ActiveSupport::Concern

  private

  # saves a security_events row with the event name, the user it's about
  # (nil when there isn't one), and the IP address of the request
  def record_security_event(event_type, user)
    SecurityEvent.create!(
      event_type: event_type,
      user: user,
      ip_address: request.remote_ip
    )
  end
end

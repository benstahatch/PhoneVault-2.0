module SecurityEventLogging
  extend ActiveSupport::Concern

  private

  # saves a security_events row with the event name, the user it's about
  # (nil when there isn't one), and the IP address of the request.
  # subject is the device, backup run, or file involved; details is a short readable summary.
  def record_security_event(event_type, user, subject: nil, details: nil)
    SecurityEvent.create!(
      event_type: event_type,
      user: user,
      subject: subject,
      details: details&.truncate(SecurityEvent::DETAILS_LIMIT),
      ip_address: request.remote_ip
    )
  end
end

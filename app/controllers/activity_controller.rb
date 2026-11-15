# Shows the logged-in user their own security events, newest first.
class ActivityController < ApplicationController
  LIMIT = 100

  def index
    # current_user.security_events only ever returns this user's rows
    @events = current_user.security_events.order(created_at: :desc, id: :desc).limit(LIMIT).load
  end
end

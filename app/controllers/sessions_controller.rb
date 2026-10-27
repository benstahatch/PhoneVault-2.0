class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  # allow 10 login attempts per IP address every 3 minutes to slow down password guessing
  rate_limit to: 10, within: 3.minutes, only: :create, with: :login_rate_limited

  def new
  end

  def create
    credentials = params.expect(session: %i[username password])

    user = User.authenticate_by(
      username: credentials[:username],
      password: credentials[:password]
    )

    if user
      reset_session
      session[:user_id] = user.id

      record_security_event("LOGIN_SUCCESS", user)
      redirect_to dashboard_path, notice: "Logged in successfully."
    else
      record_security_event("LOGIN_FAILED", targeted_user)
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    # record the logout before reset_session clears who the user was
    record_security_event("LOGOUT", current_user)

    reset_session
    redirect_to login_path, notice: "Logged out successfully."
  end

  private

  # runs instead of create once an IP address goes over the login rate limit
  def login_rate_limited
    record_security_event("LOGIN_RATE_LIMITED", targeted_user)
    redirect_to login_path, alert: "Too many login attempts. Try again in a few minutes."
  end

  # the account a login attempt was aimed at, or nil when the username doesn't exist,
  # so attempts on fake usernames are still recorded without a user
  def targeted_user
    User.find_by(username: params.dig(:session, :username))
  end

  def record_security_event(event_type, user)
    SecurityEvent.create!(
      event_type: event_type,
      user: user,
      ip_address: request.remote_ip
    )
  end
end

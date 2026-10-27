class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

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
      # link the failure to the account being targeted when that username exists,
      # otherwise store it with no user so attempts on fake usernames still show up
      targeted_user = User.find_by(username: credentials[:username])

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

  def record_security_event(event_type, user)
    SecurityEvent.create!(
      event_type: event_type,
      user: user,
      ip_address: request.remote_ip
    )
  end
end

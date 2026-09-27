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

      redirect_to dashboard_path, notice: "Logged in successfully."
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out successfully."
  end
end

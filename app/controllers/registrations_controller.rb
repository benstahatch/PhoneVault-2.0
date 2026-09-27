class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    user_params = params.expect(user: %i[
      username
      display_name
      password
      password_confirmation
    ])

    @user = User.new(user_params)

    if @user.save
      reset_session
      session[:user_id] = @user.id

      redirect_to dashboard_path, notice: "Account created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end
end

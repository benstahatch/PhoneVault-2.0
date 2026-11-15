module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  # reset_session first gives the logged-in user a new session id (prevents session fixation)
  def start_session(user)
    reset_session
    session[:user_id] = user.id
  end

  def require_login
    redirect_to login_path unless current_user
  end
end

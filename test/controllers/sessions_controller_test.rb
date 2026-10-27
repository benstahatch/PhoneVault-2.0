require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "successful login records LOGIN_SUCCESS for the user" do
    assert_difference("SecurityEvent.count", 1) do
      log_in "alice", "secret123"
    end

    assert_redirected_to dashboard_path

    event = SecurityEvent.order(:id).last
    assert_equal "LOGIN_SUCCESS", event.event_type
    assert_equal users(:alice), event.user
    assert_equal "127.0.0.1", event.ip_address
  end

  test "wrong password records LOGIN_FAILED for the targeted user" do
    assert_difference("SecurityEvent.count", 1) do
      log_in "alice", "wrongpassword"
    end

    assert_response :unprocessable_entity

    event = SecurityEvent.order(:id).last
    assert_equal "LOGIN_FAILED", event.event_type
    assert_equal users(:alice), event.user
  end

  test "unknown username records LOGIN_FAILED with no user" do
    assert_difference("SecurityEvent.count", 1) do
      log_in "nobody", "wrongpassword"
    end

    assert_response :unprocessable_entity

    event = SecurityEvent.order(:id).last
    assert_equal "LOGIN_FAILED", event.event_type
    assert_nil event.user
  end

  test "failed login does not log the user in" do
    log_in "alice", "wrongpassword"

    get dashboard_path
    assert_redirected_to login_path
  end

  test "logout records LOGOUT for the user and ends the session" do
    log_in "alice", "secret123"

    assert_difference("SecurityEvent.count", 1) do
      delete logout_path
    end

    assert_redirected_to login_path

    event = SecurityEvent.order(:id).last
    assert_equal "LOGOUT", event.event_type
    assert_equal users(:alice), event.user

    # the session is gone, so protected pages send us back to login
    get dashboard_path
    assert_redirected_to login_path
  end

  test "the 11th login attempt is blocked and records LOGIN_RATE_LIMITED" do
    10.times { log_in "alice", "wrongpassword" }
    assert_response :unprocessable_entity

    assert_difference("SecurityEvent.count", 1) do
      log_in "alice", "wrongpassword"
    end

    assert_redirected_to login_path
    assert_equal "Too many login attempts. Try again in a few minutes.", flash[:alert]

    event = SecurityEvent.order(:id).last
    assert_equal "LOGIN_RATE_LIMITED", event.event_type
    assert_equal users(:alice), event.user
  end

  test "the correct password is still blocked while rate limited" do
    10.times { log_in "alice", "wrongpassword" }

    log_in "alice", "secret123"

    assert_redirected_to login_path
    assert_equal "LOGIN_RATE_LIMITED", SecurityEvent.order(:id).last.event_type

    get dashboard_path
    assert_redirected_to login_path
  end

  test "logins are allowed again after the rate limit window passes" do
    10.times { log_in "alice", "wrongpassword" }

    travel 3.minutes + 1.second do
      log_in "alice", "secret123"
    end

    assert_redirected_to dashboard_path
  end

  private

  def log_in(username, password)
    post login_path, params: { session: { username: username, password: password } }
  end
end

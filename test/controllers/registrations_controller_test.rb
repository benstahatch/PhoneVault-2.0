require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signup username field turns off phone autocorrect and capitalization" do
    get signup_path

    assert_select "input[name='user[username]'][autocapitalize='none'][autocorrect='off'][spellcheck='false']"
  end

  test "signup form loads without logging in" do
    get signup_path

    assert_response :success
    assert_match "Create a PhoneVault Account", response.body
  end

  test "successful signup creates the user and logs them in" do
    assert_difference("User.count", 1) do
      sign_up
    end

    user = User.find_by!(username: "newuser")
    assert_equal "New User", user.display_name
    assert_equal user.id, session[:user_id]
    assert_redirected_to dashboard_path

    # the new session works for pages that require login
    get dashboard_path
    assert_response :success
  end

  test "successful signup records ACCOUNT_CREATED for the new user" do
    assert_difference("SecurityEvent.count", 1) do
      sign_up
    end

    event = SecurityEvent.order(:id).last
    assert_equal "ACCOUNT_CREATED", event.event_type
    assert_equal User.find_by!(username: "newuser"), event.user
    assert_equal "127.0.0.1", event.ip_address
  end

  test "signup saves the username lowercase without surrounding spaces" do
    sign_up username: "  NewUser  "

    assert User.exists?(username: "newuser")
  end

  test "signup while logged in switches the session to the new account" do
    post login_path, params: { session: { username: "alice", password: "secret123" } }

    sign_up

    assert_equal User.find_by!(username: "newuser").id, session[:user_id]
  end

  test "signup rejects a username that is already taken, ignoring case" do
    # a rejected signup creates no account, so there's no ACCOUNT_CREATED event either
    assert_no_difference([ "User.count", "SecurityEvent.count" ]) do
      sign_up username: "ALICE"
    end

    assert_response :unprocessable_entity
    assert_match "Username has already been taken", response.body
    assert_nil session[:user_id]
  end

  test "signup rejects mismatched password confirmation" do
    assert_no_difference("User.count") do
      sign_up password_confirmation: "different123"
    end

    assert_response :unprocessable_entity
    assert_match "Password confirmation doesn&#39;t match Password", response.body
  end

  test "signup rejects a password shorter than 8 characters" do
    assert_no_difference("User.count") do
      sign_up password: "short", password_confirmation: "short"
    end

    assert_response :unprocessable_entity
    assert_match "Password is too short", response.body
  end

  test "signup rejects usernames with characters other than letters, numbers, and underscores" do
    assert_no_difference("User.count") do
      sign_up username: "new user!"
    end

    assert_response :unprocessable_entity
    assert_match "may only contain letters, numbers, and underscores", response.body
  end

  test "signup rejects a blank display name" do
    assert_no_difference("User.count") do
      sign_up display_name: ""
    end

    assert_response :unprocessable_entity
    assert_match "Display name can&#39;t be blank", response.body
  end

  private

  # submits the signup form with valid values unless a test overrides one
  def sign_up(**overrides)
    fields = {
      username: "newuser",
      display_name: "New User",
      password: "password123",
      password_confirmation: "password123"
    }.merge(overrides)

    post signup_path, params: { user: fields }
  end
end

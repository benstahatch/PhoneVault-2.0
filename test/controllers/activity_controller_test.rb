require "test_helper"

class ActivityControllerTest < ActionDispatch::IntegrationTest
  test "activity requires login" do
    get activity_path
    assert_redirected_to login_path
  end

  test "activity lists only the current user's events" do
    SecurityEvent.create!(user: users(:alice), event_type: "BACKUP_SUCCESS", details: "alice-photo.png to Alice Phone")
    SecurityEvent.create!(user: users(:bob), event_type: "BACKUP_SUCCESS", details: "bob-secret.png to Bob Phone")
    SecurityEvent.create!(user: nil, event_type: "LOGIN_FAILED", ip_address: "203.0.113.9")
    sign_in_as users(:alice)

    get activity_path

    assert_response :success
    assert_match "alice-photo.png to Alice Phone", response.body
    assert_no_match "bob-secret.png", response.body
    assert_no_match "203.0.113.9", response.body
  end

  test "activity shows plain-language labels, details, and the IP address, newest first" do
    SecurityEvent.create!(user: users(:alice), event_type: "DEVICE_RENAMED", details: "Old Phone → Alice Phone",
      ip_address: "192.168.1.20", created_at: 2.days.ago)
    SecurityEvent.create!(user: users(:alice), event_type: "FILE_RESTORED", details: "notes.txt from Alice Phone",
      created_at: 1.day.ago)
    sign_in_as users(:alice)

    get activity_path

    # signing in adds LOGIN_SUCCESS, the newest event
    types = css_select("li[data-event-type]").map { |item| item["data-event-type"] }
    assert_equal %w[LOGIN_SUCCESS FILE_RESTORED DEVICE_RENAMED], types
    assert_select "li[data-event-type=DEVICE_RENAMED]", text: /Renamed a device: Old Phone → Alice Phone/
    assert_select "li[data-event-type=DEVICE_RENAMED]", text: /from 192\.168\.1\.20/
    assert_select "li[data-event-type=FILE_RESTORED]", text: /Restored a file: notes\.txt from Alice Phone/
  end

  test "failed sign-ins and storage problems are highlighted" do
    SecurityEvent.create!(user: users(:alice), event_type: "LOGIN_FAILED", ip_address: "203.0.113.5")
    sign_in_as users(:alice)

    get activity_path

    assert_select "li[data-event-type=LOGIN_FAILED].bg-red-50", text: /Failed sign-in attempt/
    assert_select "li[data-event-type=LOGIN_SUCCESS].bg-red-50", count: 0
  end

  test "details are escaped so a filename can't add HTML to the page" do
    SecurityEvent.create!(user: users(:alice), event_type: "BACKUP_SUCCESS", details: "<img src=x onerror=alert(1)>.png to Alice Phone")
    sign_in_as users(:alice)

    get activity_path

    assert_select "li[data-event-type=BACKUP_SUCCESS] img", count: 0
    assert_match "&lt;img src=x onerror=alert(1)&gt;.png", response.body
  end

  test "activity shows at most the latest 100 events" do
    105.times { |n| SecurityEvent.create!(user: users(:alice), event_type: "LOGOUT", created_at: (200 - n).minutes.ago) }
    sign_in_as users(:alice)

    get activity_path

    assert_select "li[data-event-type]", count: ActivityController::LIMIT
    assert_match "Showing the latest 100 events.", response.body
  end

  test "the header links to the activity page" do
    sign_in_as users(:alice)

    get dashboard_path

    assert_select ".site-nav a[href='#{activity_path}']", text: "Activity"
  end

  private

  def sign_in_as(user, password: "secret123")
    post login_path, params: { session: { username: user.username, password: password } }
  end
end

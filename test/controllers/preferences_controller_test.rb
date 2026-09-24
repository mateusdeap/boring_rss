require "test_helper"

class PreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "updates the signed-in user's theme" do
    patch preferences_path, params: { user: { theme: "dark" } }

    assert_redirected_to root_path
    assert_equal "dark", users(:one).reload.theme
  end

  test "toggles unread-only and returns to the given feed" do
    patch preferences_path, params: { user: { unread_only: "true" }, return_to: feed_path(feeds(:one)) }

    assert_redirected_to feed_path(feeds(:one))
    assert users(:one).reload.unread_only?
  end

  test "ignores an off-site return_to" do
    patch preferences_path, params: { user: { unread_only: "true" }, return_to: "https://evil.example.com/" }

    assert_redirected_to root_path
  end

  test "requires authentication" do
    sign_out

    patch preferences_path, params: { user: { theme: "dark" } }

    assert_redirected_to new_session_path
  end
end

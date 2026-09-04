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

  test "requires authentication" do
    sign_out

    patch preferences_path, params: { user: { theme: "dark" } }

    assert_redirected_to new_session_path
  end
end

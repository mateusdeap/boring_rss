require "test_helper"

class PollsControllerTest < ActionDispatch::IntegrationTest
  test "polls only the signed-in user's feeds" do
    sign_in_as users(:one)

    assert_enqueued_with(job: UpdateFeedsJob, args: [ { user_id: users(:one).id } ]) do
      post poll_url
    end

    assert_redirected_to root_path
  end
end

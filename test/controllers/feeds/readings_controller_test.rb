require "test_helper"

class Feeds::ReadingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @feed = feeds(:one)
  end

  test "marks every item in the feed read and returns to the feed" do
    @feed.items.update_all(read: false)

    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      post feed_reading_url(@feed)
    end

    assert_redirected_to feed_url(@feed)
    assert_equal 0, @feed.unread_count
  end

  test "leaves other feeds alone" do
    feeds(:two).items.update_all(read: false)

    post feed_reading_url(@feed)

    assert feeds(:two).unread_count.positive?
  end

  test "another user's feed is not found" do
    post feed_reading_url(feeds(:two))

    assert_response :not_found
  end
end

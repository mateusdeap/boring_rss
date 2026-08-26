require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "unread_count reflects only unread items" do
    feed = feeds(:one)
    feed.items.update_all(read: false)

    assert_equal feed.items.count, feed.unread_count

    feed.items.first.update!(read: true)

    assert_equal feed.items.count - 1, feed.unread_count
  end
end

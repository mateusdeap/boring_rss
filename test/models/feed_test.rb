require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "unread_count reflects only unread items" do
    feed = feeds(:one)
    feed.items.update_all(read: false)

    assert_equal feed.items.count, feed.unread_count

    feed.items.first.update!(read: true)

    assert_equal feed.items.count - 1, feed.unread_count
  end

  test "record_fetch_failure! sets the timestamp and broadcasts the row" do
    feed = feeds(:one)

    assert_turbo_stream_broadcasts :feeds, count: 1 do
      feed.record_fetch_failure!
    end

    assert feed.last_fetch_error_at.present?
  end

  test "record_fetch_success! clears a previous failure and broadcasts the row" do
    feed = feeds(:one)
    feed.update!(last_fetch_error_at: 1.hour.ago)

    assert_turbo_stream_broadcasts :feeds, count: 1 do
      feed.record_fetch_success!
    end

    assert_nil feed.last_fetch_error_at
  end

  test "record_fetch_success! is a no-op when there was no failure" do
    feed = feeds(:one)
    assert_nil feed.last_fetch_error_at

    assert_no_turbo_stream_broadcasts :feeds do
      feed.record_fetch_success!
    end
  end
end

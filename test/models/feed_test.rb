require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "unread_count reflects only unread items" do
    feed = feeds(:one)
    feed.items.update_all(read: false)

    assert_equal feed.items.count, feed.unread_count

    feed.items.first.update!(read: true)

    assert_equal feed.items.count - 1, feed.unread_count
  end

  test "record_fetch! with a failure starts a failure streak, logs it, and broadcasts the row" do
    feed = feeds(:one)

    assert_difference -> { feed.fetch_events.count } do
      assert_turbo_stream_broadcasts [ feed.user, :feeds ], count: 1 do
        feed.record_fetch!(status: "503", detail: "Service Unavailable", bytes: 120)
      end
    end

    assert feed.fetch_failed?
    assert_equal "503", feed.last_fetch_status
    assert_equal 1, feed.fetch_failures_count
    assert feed.last_fetched_at.present?

    feed.record_fetch!(status: "TIMEOUT", detail: "Net::OpenTimeout: execution expired")
    assert_equal 2, feed.fetch_failures_count
  end

  test "record_fetch! with a success clears the failure streak and stores validators" do
    feed = feeds(:one)
    feed.update!(last_fetch_error_at: 1.hour.ago, fetch_failures_count: 3)

    feed.record_fetch!(status: "200", detail: "RSS · 3 entries · 1 new", new_items_count: 1, etag: %("abc"), last_modified: "Wed, 23 Sep 2026 10:00:00 GMT")

    assert_not feed.fetch_failed?
    assert_equal 0, feed.fetch_failures_count
    assert_equal %("abc"), feed.etag
    assert_equal "Wed, 23 Sep 2026 10:00:00 GMT", feed.last_modified
  end

  test "record_fetch! keeps stored validators when a 304 omits them" do
    feed = feeds(:one)
    feed.update!(etag: %("abc"))

    feed.record_fetch!(status: "304", detail: "Not modified")

    assert_equal %("abc"), feed.etag
    assert_not feed.fetch_failed?
  end
end

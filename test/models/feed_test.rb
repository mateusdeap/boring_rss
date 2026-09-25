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
      # The feed row, its feed header in a river, and the Groups rows
      # showing it: All feeds, Ungrouped.
      assert_turbo_stream_broadcasts [ feed.user, :feeds ], count: 4 do
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

  test "stale when the newest item is older than three usual gaps, and never before 14 days" do
    feed = feeds(:one)
    feed.update!(last_fetched_at: Time.current)

    feed.update!(items_per_week: 7, last_item_at: 5.days.ago)
    assert_not feed.stale?, "3 gaps is 3 days, but 14 days is the floor"
    feed.update!(last_item_at: 15.days.ago)
    assert feed.stale?
    assert_equal "stale", feed.health

    feed.update!(items_per_week: 0.5, last_item_at: 30.days.ago)
    assert_not feed.stale?, "one item every two weeks: stale after six"
    feed.update!(last_item_at: 43.days.ago)
    assert feed.stale?

    feed.update!(last_item_at: nil)
    assert_not feed.stale?, "a feed with no items is never stale"
  end

  test "a failing feed reads as fail, not stale" do
    feed = feeds(:one)
    feed.update!(last_fetched_at: Time.current, last_fetch_error_at: Time.current, last_item_at: 1.year.ago)

    assert_equal "fail", feed.health
  end

  test "refresh_volume! counts items per week over the last eight weeks and keeps the newest item's time" do
    feed = feeds(:one)
    feed.items.delete_all
    16.times { |n| feed.items.create!(title: "Recent #{n}", published_at: (n * 3).days.ago) }
    feed.items.create!(title: "Old", published_at: 100.days.ago)

    feed.refresh_volume!

    assert_in_delta 2.0, feed.items_per_week
    assert_in_delta Time.current, feed.last_item_at, 1.minute
  end

  test "failures back off: 30 min, 1 h, 2 h, 4 h, then every 6 h, counting attempts to 8; a success resets" do
    feed = feeds(:one)

    freeze_time do
      started = Time.current
      delays = 9.times.map do
        feed.record_fetch!(status: "503", detail: "Service Unavailable")
        (feed.next_fetch_at - Time.current).to_i / 60
      end

      assert_equal [ 30, 60, 120, 240, 360, 360, 360, 360, 360 ], delays
      assert_equal started, feed.failing_since
      assert_match "(attempt 8/8)", feed.fetch_events.recent.second.detail
      assert_match "(every 6 h)", feed.fetch_events.recent.first.detail

      feed.record_fetch!(status: "200", detail: "RSS", bytes: 10)
      assert_nil feed.failing_since
      assert_equal 0, feed.fetch_failures_count
      assert_equal Time.current + 30.minutes, feed.next_fetch_at
      assert_equal [ Time.current, "200", 10 ], [ feed.last_ok_at, feed.last_ok_status, feed.last_ok_bytes ]
    end
  end

  test "a failure keeps the last OK fetch and the hub" do
    feed = feeds(:one)
    feed.update!(last_ok_at: 1.day.ago, last_ok_status: "200", websub_hub: "https://hub.example.com/")

    feed.record_fetch!(status: "TIMEOUT", detail: "Net::OpenTimeout")

    assert_equal "200", feed.last_ok_status
    assert_equal "https://hub.example.com/", feed.websub_hub
  end
end

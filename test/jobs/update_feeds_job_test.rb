require "test_helper"

class UpdateFeedsJobTest < ActiveJob::TestCase
  RSS_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <title>Example</title><link>https://example.com/</link><description>d</description>
      <item><title>Existing</title><link>https://example.com/existing</link><guid>existing-guid</guid></item>
      <item><title>Fresh</title><link>https://example.com/fresh</link><guid>fresh-guid</guid></item>
    </channel></rss>
  XML

  test "records a fetch failure with its state word without blocking other feeds" do
    failing = feeds(:one)
    healthy = feeds(:two)

    not_modified = response(304)

    with_fetch_stub(->(url, **) { url == failing.feed_url ? raise(Errno::ECONNREFUSED) : not_modified }) do
      UpdateFeedsJob.perform_now
    end

    assert failing.reload.fetch_failed?
    assert_equal "CONN", failing.last_fetch_status
    assert_match "Errno::ECONNREFUSED", failing.last_fetch_detail
    assert_not healthy.reload.fetch_failed?
    assert_equal "304", healthy.last_fetch_status
  end

  test "records an HTTP error status with its reason phrase" do
    feed = feeds(:one)

    unavailable = response(503, reason: "Service Unavailable", body: "down")

    with_fetch_stub(->(*, **) { unavailable }) do
      UpdateFeedsJob.perform_now
    end

    event = feed.fetch_events.recent.first
    assert_equal "503", event.status
    assert_match(/\AService Unavailable · retry \d\d:\d\dZ \(attempt 1\/8\)\z/, event.detail)
    assert_equal 4, event.bytes
    assert feed.reload.fetch_failed?
  end

  test "appends only new entries and logs the count, clearing a previous failure" do
    feed = feeds(:one)
    feed.update!(last_fetch_error_at: 1.hour.ago, fetch_failures_count: 2)
    feed.items.create!(title: "Existing", link: "https://example.com/existing", guid: "existing-guid")

    ok = response(200, body: RSS_BODY, etag: %("v2"))

    with_fetch_stub(->(*, **) { ok }) do
      assert_difference -> { feed.items.count }, 1 do
        UpdateFeedsJob.perform_now
      end
    end

    feed.reload
    assert_not feed.fetch_failed?
    assert_equal %("v2"), feed.etag
    event = feed.fetch_events.recent.first
    assert_equal 1, event.new_items_count
    assert_equal %(RSS · 2 entries · 1 new · ETag "v2"), event.detail
  end

  test "sends the stored validators as a conditional GET" do
    feed = feeds(:one)
    feed.update!(etag: %("v1"), last_modified: "Wed, 23 Sep 2026 10:00:00 GMT")
    seen = {}
    not_modified = response(304)

    with_fetch_stub(->(url, etag:, last_modified:) { seen[url] = [ etag, last_modified ]; not_modified }) do
      UpdateFeedsJob.perform_now
    end

    assert_equal [ %("v1"), "Wed, 23 Sep 2026 10:00:00 GMT" ], seen[feed.feed_url]
  end

  test "a non-XML body is a parse failure, never handed to RSS::Parser as a URL or path" do
    feed = feeds(:one)

    not_xml = response(200, body: "/etc/hosts")

    with_fetch_stub(->(*, **) { not_xml }) do
      UpdateFeedsJob.perform_now
    end

    assert_equal "PARSE", feed.reload.last_fetch_status
  end

  test "the recurring run polls only feeds that are due; asked for, a user's or one feed's poll ignores the schedule" do
    due = feeds(:one)
    later = feeds(:two)
    due.update!(next_fetch_at: 1.minute.ago)
    later.update!(next_fetch_at: 10.minutes.from_now)
    polled = []
    not_modified = response(304)

    with_fetch_stub(->(url, **) { polled << url; not_modified }) do
      UpdateFeedsJob.perform_now
      assert_equal [ due.feed_url ], polled

      polled.clear
      UpdateFeedsJob.perform_now(feed_id: later.id)
      assert_equal [ later.feed_url ], polled
    end
  end

  test "a success schedules the next poll and records it as the last OK fetch, with the feed's WebSub hub" do
    feed = feeds(:one)
    body = RSS_BODY.sub("<channel>", %(<channel><atom:link xmlns:atom="http://www.w3.org/2005/Atom" rel="hub" href="https://hub.example.com/"/>))
    ok = response(200, body:)

    freeze_time do
      with_fetch_stub(->(*, **) { ok }) { UpdateFeedsJob.perform_now }

      feed.reload
      assert_equal Time.current + Feed::POLL_INTERVAL, feed.next_fetch_at
      assert_equal [ Time.current, "200", body.bytesize ], [ feed.last_ok_at, feed.last_ok_status, feed.last_ok_bytes ]
      assert_equal "https://hub.example.com/", feed.websub_hub
      assert feed.last_item_at.present?
    end
  end

  private

  def response(status, reason: "OK", body: "", etag: nil)
    FeedFetcher::Response.new(status:, reason:, body:, etag:, last_modified: nil, url: "https://example.com/rss", redirects: [])
  end

  # No mocking gem is available: Minitest 6 dropped Object#stub/Minitest::Mock
  # from core (verified — the installed minitest-6.0.6 gem ships no mock.rb
  # at all), so this swaps the class method directly instead. The lambda
  # runs with self = FeedFetcher, so build any responses outside it.
  def with_fetch_stub(replacement)
    original = FeedFetcher.method(:fetch)
    FeedFetcher.define_singleton_method(:fetch, &replacement)
    yield
  ensure
    FeedFetcher.define_singleton_method(:fetch, original)
  end
end

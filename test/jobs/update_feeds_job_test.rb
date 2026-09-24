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
    assert_equal "Service Unavailable", event.detail
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

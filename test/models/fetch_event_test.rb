require "test_helper"

class FetchEventTest < ActiveSupport::TestCase
  test "tone maps statuses to RDR-01 StatusCode tones" do
    assert_equal "ok", FetchEvent.tone("200")
    assert_equal "ok", FetchEvent.tone("304")
    assert_equal "warn", FetchEvent.tone("301")
    assert_equal "fail", FetchEvent.tone("404")
    assert_equal "fail", FetchEvent.tone("503")
    assert_equal "fail", FetchEvent.tone("TIMEOUT")
  end

  test "prune deletes only events older than the retention window" do
    feed = feeds(:one)
    old = feed.fetch_events.create!(status: "200", created_at: 2.days.ago)
    recent = feed.fetch_events.create!(status: "200", created_at: 1.hour.ago)

    FetchEvent.prune

    assert_not FetchEvent.exists?(old.id)
    assert FetchEvent.exists?(recent.id)
  end

  test "creating an event prepends it to the feed's log stream" do
    feed = feeds(:one)

    assert_turbo_stream_broadcasts feed, count: 1 do
      feed.fetch_events.create!(status: "200", detail: "RSS · 1 entries · 0 new")
    end
  end
end

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

  test "prune keeps each feed's newest events, however old" do
    one = feeds(:one)
    two = feeds(:two)
    oldest = one.fetch_events.create!(status: "200", created_at: 3.days.ago)
    kept = 2.times.map { |n| one.fetch_events.create!(status: "200", created_at: n.hours.ago) }
    other = two.fetch_events.create!(status: "200", created_at: 30.days.ago)

    FetchEvent.prune(keep: 2)

    assert_not FetchEvent.exists?(oldest.id)
    assert kept.all? { |event| FetchEvent.exists?(event.id) }
    assert FetchEvent.exists?(other.id)
  end

  test "creating an event prepends it to the feed's log stream" do
    feed = feeds(:one)

    assert_turbo_stream_broadcasts feed, count: 1 do
      feed.fetch_events.create!(status: "200", detail: "RSS · 1 entries · 0 new")
    end
  end
end

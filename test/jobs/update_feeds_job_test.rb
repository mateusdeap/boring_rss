require "test_helper"

class UpdateFeedsJobTest < ActiveJob::TestCase
  test "records a fetch failure without blocking other feeds" do
    failing = feeds(:one)
    healthy = feeds(:two)
    empty_feed = Struct.new(:entries).new([])

    with_parsed_feed_stub(->(url) { url == failing.feed_url ? raise(Errno::ECONNREFUSED) : empty_feed }) do
      UpdateFeedsJob.perform_now
    end

    assert failing.reload.last_fetch_error_at.present?
    assert_nil healthy.reload.last_fetch_error_at
  end

  test "clears a previous fetch failure once the feed succeeds again" do
    feed = feeds(:one)
    feed.update!(last_fetch_error_at: 1.hour.ago)
    empty_feed = Struct.new(:entries).new([])

    with_parsed_feed_stub(->(_url) { empty_feed }) do
      UpdateFeedsJob.perform_now
    end

    assert_nil feed.reload.last_fetch_error_at
  end

  private

  # No mocking gem is available: Minitest 6 dropped Object#stub/Minitest::Mock
  # from core (verified — the installed minitest-6.0.6 gem ships no mock.rb
  # at all), so this swaps the class method directly instead.
  def with_parsed_feed_stub(replacement)
    original = ParsedFeed.method(:parse)
    ParsedFeed.define_singleton_method(:parse, &replacement)
    yield
  ensure
    ParsedFeed.define_singleton_method(:parse, original)
  end
end

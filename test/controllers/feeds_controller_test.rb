require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "create re-renders the dialog with a field error for an invalid feed" do
    assert_no_difference("Feed.count") do
      post feeds_url, params: { feed: { link: "this is not xml or a url" } }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_match "Couldn&#39;t find a feed at that address.", response.body
  end

  test "create accepts an Atom feed missing a feed-level author tag" do
    # Real, reproduced bug: RSS::Parser's default strict validation rejects
    # this — https://37signals.com/feed/jobs.xml is a live example — even
    # though the feed is otherwise complete and functional. `normalize_rss`
    # (rss gem) treats any string containing "<" as inline XML rather than
    # a URL, so this hits the exact same parse path with no network call.
    atom_feed = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Jobs</title>
        <id>tag:example.com,2026:jobs</id>
        <updated>2026-01-01T00:00:00Z</updated>
        <link href="https://example.com/jobs/"/>
      </feed>
    XML

    assert_difference("Feed.count") do
      post feeds_url, params: { feed: { link: atom_feed } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "Jobs", Feed.last.title
  end
end

class InitializeFeed
  def initialize(link:)
    @link = link
  end

  def call
    parsed_feed = ParsedFeed.parse(@link)
    Feed.new(
      feed_url: @link,
      title: parsed_feed.title,
      description: parsed_feed.description,
      link: parsed_feed.link,
      items: InitializeItems.new(parsed_feed.entries).call
    )
  rescue RSS::Error
    feed = Feed.new
    feed.errors.add(:link, "Invalid link")
    feed
  end
end

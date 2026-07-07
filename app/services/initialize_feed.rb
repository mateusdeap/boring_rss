class InitializeFeed
  def initialize(link:)
    @link = link
  end

  def call
    parsed_feed = RSS::Parser.parse(@link)
    Feed.new(
      title: parsed_feed.channel.title,
      description: parsed_feed.channel.description,
      link: parsed_feed.channel.link,
      items: InitializeItems.new(parsed_feed.channel.items).call
    )
  rescue RSS::NotWellFormedError
    feed = Feed.new
    feed.errors.add(:link, "Invalid link")
    feed
  end
end

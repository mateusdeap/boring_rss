class UpdateFeedsJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Updating Feeds..."
    feeds = Feed.all
    feeds.each do |feed|
      items = RSS::Parser.parse(feed.feed_url).channel.items
      most_recent_item_published_at = feed.items.order(published_at: :desc)[0].published_at
      new_parsed_items = items.select { |item| item.pubDate > most_recent_item_published_at }
      new_items = InitializeItems.new(new_parsed_items).call
      feed.items << new_items
    end
  end
end

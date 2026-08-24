class UpdateFeedsJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Updating Feeds..."
    feeds = Feed.all
    feeds.each do |feed|
      parsed_feed = ParsedFeed.parse(feed.feed_url)
      existing_identities = feed.items.pluck(:guid, :link).map { |guid, link| guid.presence || link }.to_set
      new_entries = parsed_feed.entries.reject { |entry| existing_identities.include?(entry.guid.presence || entry.link) }
      new_items = InitializeItems.new(new_entries).call
      feed.items << new_items
    rescue RSS::Error => e
      Rails.logger.warn("Skipping feed #{feed.id} (#{feed.feed_url}): #{e.message}")
    end
  end
end

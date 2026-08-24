class InitializeItems
  def initialize(parsed_items)
    @parsed_items = parsed_items
  end

  def call
    @parsed_items.map do |item|
      Item.new(
        title: item.title,
        summary: item.description,
        link: item.link,
        published_at: item.pubDate
      )
    end
  end
end

class InitializeItems
  def initialize(parsed_entries)
    @parsed_entries = parsed_entries
  end

  def call
    @parsed_entries.map do |entry|
      Item.new(
        title: entry.title,
        summary: entry.summary,
        link: entry.link,
        guid: entry.guid,
        published_at: entry.published_at
      )
    end
  end
end

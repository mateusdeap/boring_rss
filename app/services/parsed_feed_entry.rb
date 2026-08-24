class ParsedFeedEntry
  def initialize(entry, atom:)
    @entry = entry
    @atom = atom
  end

  def title
    @atom ? @entry.title&.content : @entry.title
  end

  def summary
    @atom ? (@entry.summary&.content || @entry.content&.content) : @entry.description
  end

  def link
    @atom ? AtomLink.alternate(@entry.links) : @entry.link
  end

  def guid
    @atom ? @entry.id&.content : @entry.guid&.content
  end

  def published_at
    @atom ? (@entry.published&.content || @entry.updated&.content) : @entry.pubDate
  end
end

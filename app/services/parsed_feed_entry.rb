class ParsedFeedEntry
  # The feed element an entry's body comes from, best first. Full content is
  # RSS <content:encoded> or Atom <content>; RSS <description> and Atom
  # <summary> are excerpts. Decided from markup alone — no word-count
  # heuristics (reading pane spec, "Summary detection").
  Body = Data.define(:html, :kind, :source)

  def initialize(entry, atom:)
    @entry = entry
    @atom = atom
  end

  def title
    @atom ? @entry.title&.content : @entry.title
  end

  # The HTML to show: full content when the feed sends it, else the excerpt.
  def summary
    body.html
  end

  def body
    @body ||=
      if (full = @atom ? @entry.content&.content : @entry.content_encoded).present?
        Body.new(html: full, kind: "full", source: @atom ? "content" : "content:encoded")
      elsif (excerpt = @atom ? @entry.summary&.content : @entry.description).present?
        Body.new(html: excerpt, kind: "excerpt", source: @atom ? "summary" : "description")
      else
        Body.new(html: nil, kind: "empty", source: nil)
      end
  end

  # Atom <author><name>, else RSS <dc:creator>, else RSS <author> (an email
  # address, often with the name in parentheses).
  def author
    if @atom
      @entry.author&.name&.content
    else
      @entry.dc_creator.presence || @entry.author
    end
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

class ParsedFeed
  # do_validate: false — a real feed reader has to be lenient. Strict Atom
  # schema validation (the rss gem's default) rejects feeds that are
  # extremely common and functionally fine in the wild, e.g. one missing a
  # feed-level <author> (verified: https://37signals.com/feed/jobs.xml
  # raises RSS::MissingTagError under the default, parses cleanly with this
  # off). ParsedFeed/ParsedFeedEntry already navigate every field with `&.`,
  # so a field genuinely absent even under lenient parsing just comes back
  # nil rather than raising — Feed's own `validates_presence_of :link`
  # remains the actual backstop against an unusably broken feed.
  def self.parse(source)
    new(RSS::Parser.parse(source, false))
  end

  def initialize(document)
    @document = document
  end

  def title
    atom? ? @document.title&.content : @document.channel.title
  end

  def description
    atom? ? @document.subtitle&.content : @document.channel.description
  end

  def link
    atom? ? AtomLink.alternate(@document.links) : @document.channel.link
  end

  def entries
    entries = atom? ? @document.entries : @document.channel.items
    entries.map { |entry| ParsedFeedEntry.new(entry, atom: atom?) }
  end

  private

  def atom?
    @document.is_a?(RSS::Atom::Feed)
  end
end

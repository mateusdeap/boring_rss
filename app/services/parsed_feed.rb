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
    new(RSS::Parser.parse(source, false), source: source.to_s.include?("<") ? source.to_s : nil)
  end

  # Parses an already-fetched response body (FeedFetcher). RSS::Parser's
  # `normalize_rss` only treats a string as XML if it contains "<" —
  # anything else it tries as a URL to fetch or a local file path to read.
  # A fetched body must never be interpreted that way, so reject it here.
  def self.parse_xml(body)
    raise RSS::NotWellFormedError, "Response is not XML" unless body.include?("<")

    parse(body)
  end

  # A <link rel="hub"> (Atom, or atom:link inside RSS) names the feed's
  # WebSub hub. Read from the markup, since the rss gem doesn't parse
  # atom:link inside an RSS channel.
  HUB_LINK = /<(?:atom:)?link\b[^>]*\brel\s*=\s*["']hub["'][^>]*>/i
  HREF = /\bhref\s*=\s*["']([^"']+)["']/i

  def initialize(document, source: nil)
    @document = document
    @source = source
  end

  # The hub's URL, or nil when the feed names none (or wasn't parsed from
  # markup).
  def websub_hub
    @source&.[](HUB_LINK)&.[](HREF, 1)
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

  def format
    atom? ? "Atom" : "RSS"
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

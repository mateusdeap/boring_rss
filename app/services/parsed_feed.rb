class ParsedFeed
  def self.parse(source)
    new(RSS::Parser.parse(source))
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

module AtomLink
  module_function

  # Atom entries/feeds can carry multiple <link> elements distinguished by
  # `rel` (self, related, enclosure, ...). An unspecified `rel` defaults to
  # "alternate", which is the human-readable page we want.
  def alternate(links)
    (links.find { |link| link.rel.nil? || link.rel == "alternate" } || links.first)&.href
  end
end

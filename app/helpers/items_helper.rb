module ItemsHelper
  SAFE_LINK_SCHEMES = %w[http https].freeze

  # Rails' `sanitize` default allow-list drops table markup entirely, which
  # would silently eat any table a feed embeds. This list is what the
  # reader's `.rdr-article .r-body` rules (app/assets/tailwind/application.css)
  # actually style — deliberately not "the default list plus tables," since
  # that would also admit tags (dl/kbd/samp/mark/...) the reader has no
  # treatment for. h1/h5/h6 are allowed only to be demoted (see
  # #reader_content). The rest of the cleanup rules — attributes, URLs,
  # embeds, tracking pixels, table unwrapping — live in ReaderScrubber.
  SUMMARY_ALLOWED_TAGS = %w[
    p h1 h2 h3 h4 h5 h6 blockquote pre ul ol li hr
    table thead tbody tfoot tr td th
    figure figcaption sup sub
    a strong b em i code br img span
  ].freeze

  # Feed headings sit under the article title, the only headline: h1 and
  # h2 render as h2, h3–h6 as h3.
  HEADING_LEVELS = { "h1" => "h2", "h4" => "h3", "h5" => "h3", "h6" => "h3" }.freeze

  def safe_item_link(link)
    uri = URI.parse(link)
    uri.to_s if uri.is_a?(URI::HTTP) && SAFE_LINK_SCHEMES.include?(uri.scheme)
  rescue URI::InvalidURIError
    nil
  end

  ReaderContent = Data.define(:html, :pixels_stripped, :tables, :tables_unwrapped)

  # The item's body cleaned and restructured by ReaderScrubber (relative
  # URLs resolved against the entry's link, else the feed's URL; layout
  # tables unwrapped, data tables marked, code blocks framed), then shaped
  # for presentation only: headings demoted, images lazy.
  def reader_content(item)
    scrubber = ReaderScrubber.new(base: safe_item_link(item.link) || item.feed.feed_url)
    fragment = scrubber.clean(item.summary)

    fragment.css(HEADING_LEVELS.keys.join(",")).each { |heading| heading.name = HEADING_LEVELS[heading.name] }
    fragment.css("img").each { |img| img["loading"] = "lazy" }

    ReaderContent.new(html: fragment.to_html.html_safe, # scrubbed above
                      pixels_stripped: scrubber.pixels_stripped,
                      tables: scrubber.tables, tables_unwrapped: scrubber.tables_unwrapped)
  end

  # `example.com` for the end box's CONTINUE ON / OPEN ON.
  def link_host(link)
    URI.parse(link).host&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  # `example.com/field-notes/feed.xml` — a URL without its scheme.
  def bare_url(url)
    url.to_s.sub(%r{\Ahttps?://}, "")
  end

  # RDR-01 tones for the reader's content kind: FULL is ok; an excerpt or
  # an empty entry is a warning (the article isn't all here).
  def content_kind_tag(item)
    tag.span(item.content_kind.upcase, class: "rdr-tone rdr-tone-#{item.content_full? ? "ok" : "warn"}")
  end

  # `<content:encoded>`, or nil for items stored before the source was kept.
  def content_source_label(item)
    "<#{item.content_source}>" if item.content_source
  end

  # `200 OK` in the status's tone, or the failure word (`TIMEOUT`).
  def fetch_status_tag(feed)
    status = feed.last_fetch_status
    reason = Rack::Utils::HTTP_STATUS_CODES[status.to_i] if status.to_s.match?(/\A\d+\z/)
    tag.span([ status, reason ].compact.join(" "), class: "rdr-tone rdr-tone-#{FetchEvent.tone(status)}")
  end

  # `ETag "a91f…"`: enough to tell two validators apart.
  def short_etag(etag)
    value = etag.to_s.delete_prefix("W/").delete('"')
    %(ETag "#{value.first(4)}#{"…" if value.length > 4}")
  end

  def item_author(item)
    item.author.presence || "no author"
  end
end

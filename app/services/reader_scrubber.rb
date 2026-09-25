# The reader's cleanup rules for feed-supplied HTML (reading pane spec,
# "HTML cleanup rules" — decided 2026-09-24 — and RDR-01's Article content
# section). Use it through #clean, which runs the per-node scrub and then
# the structural passes; `sanitize(html, scrubber:)` would run only the
# per-node half.
#
# Per node (a Loofah scrubber):
# - Tags: ItemsHelper::SUMMARY_ALLOWED_TAGS, what the reader's content
#   styles cover, plus `caption` (it marks a data table). Embeds are let in
#   only to be replaced here, never kept.
# - Attributes: a short explicit list. `class` survives only as
#   `language-*`/`lang-*` on pre/code (the code label bar reads it): a
#   publisher's classes would otherwise reach the app's own CSS —
#   Tailwind's `.hidden`/`.fixed`, the `r-*`/`rdr-*` components. `width`
#   and `height` stay on images only.
# - URLs: relative href/src resolve against `base` (the entry's link,
#   else the feed's URL); anything that doesn't end up http(s) is dropped.
#   Images load straight from the publisher, upgraded to https and sent
#   with no referrer. Links open in a new tab, also without a referrer.
# - Embeds (iframe, video, audio, embed): replaced by a one-line link row,
#   `VIDEO example.com/clip.mp4 ↗` — no third-party scripts in the reader,
#   and nothing vanishes without a trace. This happens here rather than in
#   the structural passes so that no path through this class ever emits an
#   iframe; a link row and an embed classify the same way (both are block
#   content).
# - Tracking pixels (an img whose width or height attribute is 1 or less)
#   are removed and counted in #pixels_stripped. Scripts, styles and the
#   like are removed silently, contents and all (the base scrubber would
#   keep their text, as it does for any tag it drops).
#
# Then the structure, in the Article content section's order:
# 1. Spacer rows (every cell blank) and empty paragraphs are removed.
# 2. Tables are classified innermost first. Data tables get
#    `data-rdr="data"`, a `.r-table-scroll` wrapper and `data-num` on
#    numeric cells; layout tables are unwrapped into paragraphs, dropping
#    glyph cells (a lone bullet or icon). #tables / #tables_unwrapped
#    count them for the details CONTENT row.
# 3. Two or more consecutive `br` split a paragraph.
# 4. Consecutive `hr`s collapse to one; an `hr` next to a heading or at
#    either edge of the body is dropped.
# 5. `pre` is framed as a code block: label bar with the language, line
#    count and [C] COPY.
#
# Two places this differs from the letter of the section, on purpose:
# - Embeds become link rows in the per-node pass, not as the last step,
#   so no path through this class can ever emit an iframe. The output is
#   the same: a link row classifies like the embed it replaced.
# - A blank cell in a row that has content survives until its table is
#   classified (spacer *rows* go first, as specified). Removing it earlier
#   would shift a data table's columns; the section's own "empty columns"
#   rule then drops it from data tables, and unwrapping drops it from
#   layout tables.
#
# Loofah walks bottom-up, so a node's children are already scrubbed —
# their URLs resolved — when the node itself comes up.
class ReaderScrubber < Rails::HTML::PermitScrubber
  EMBEDS = { "iframe" => "EMBED", "embed" => "EMBED", "video" => "VIDEO", "audio" => "AUDIO" }.freeze
  MEDIA = %w[video audio].freeze
  ATTRIBUTES = %w[href src alt title width height datetime cite lang class].freeze
  URL_ATTRIBUTES = %w[href src].freeze
  IMAGE_ONLY_ATTRIBUTES = %w[width height].freeze
  CODE_LANGUAGE = /\A(?:language|lang)-[\w+#-]+\z/
  NO_REFERRER = "no-referrer"
  # Dropped with their contents: their text was never meant to be read.
  DROPPED_WITH_CONTENTS = %w[script style noscript template object].freeze

  # Content that isn't blank even without text.
  SUBSTANCE = %w[img iframe embed video audio hr].freeze
  BLANK_TEXT = /\A[\s\u00a0\u200b-\u200d\ufeff]*\z/
  # Phrasing content: a cell of only these becomes one paragraph, and a
  # table whose cells are all like that can be a data table.
  INLINE = %w[a strong b em i code br span sup sub].freeze
  # Any of these in a cell makes its table layout (div: an embed row).
  BLOCK = %w[p div h1 h2 h3 h4 h5 h6 ul ol blockquote pre img figure hr].freeze
  PRESENTATION_ROLES = %w[presentation none].freeze
  HEADINGS = %w[h1 h2 h3 h4 h5 h6].freeze
  # One or two symbol characters (• · › ▶ → –), emoji variation selector aside.
  GLYPH = /\A[\p{S}\p{P}]{1,2}\z/
  GLYPH_IMAGE_MAX = 24
  NUMERIC_CELL = /\A[-+−]?[$€£]?\d[\d\s,. ]*(%|[kKMG]?B|ms|s)?\z/

  # An img sized 1px or less in either direction.
  def self.pixel?(img)
    %w[width height].any? { |dimension| img[dimension].to_s.strip.match?(/\A[01](?:\.0+)?(?:px)?\z/) }
  end

  attr_reader :pixels_stripped, :tables, :tables_unwrapped

  def initialize(base:)
    super()
    @base = base
    @pixels_stripped = 0
    @tables = 0
    @tables_unwrapped = 0
    @presentation_tables = Set.new.compare_by_identity
    self.tags = ItemsHelper::SUMMARY_ALLOWED_TAGS + EMBEDS.keys + %w[source caption]
    self.attributes = ATTRIBUTES
  end

  # The cleaned fragment, ready for presentation-only shaping.
  def clean(html)
    fragment = Loofah.html5_fragment(html.to_s).scrub!(self)
    remove_spacers(fragment)
    resolve_tables(fragment)
    split_paragraphs(fragment)
    tidy_rules(fragment)
    fragment.css("pre").each { |pre| frame_code_block(pre) }
    fragment
  end

  def scrub(node)
    result = super
    return result unless node.element? && node.parent

    case node.name
    when *EMBEDS.keys then replace_embed(node)
    when "source" then node.remove unless MEDIA.include?(node.parent.name)
    when "img" then scrub_image(node)
    when "a" then scrub_link(node)
    end
    result
  end

  protected

  def scrub_node(node)
    return node.remove if DROPPED_WITH_CONTENTS.include?(node.name)

    super
  end

  def scrub_attributes(node)
    @presentation_tables << node if node.name == "table" && PRESENTATION_ROLES.include?(node["role"].to_s.strip.downcase)
    super
    scrub_class(node)
    IMAGE_ONLY_ATTRIBUTES.each { |name| node.remove_attribute(name) } unless node.name == "img"
    URL_ATTRIBUTES.each do |name|
      next unless node[name]

      url = resolve(node[name])
      url ? node[name] = url : node.remove_attribute(name)
    end
  end

  private

  # -- Per node -------------------------------------------------------------

  def scrub_class(node)
    return unless node["class"]

    languages = %w[pre code].include?(node.name) ? node["class"].split.grep(CODE_LANGUAGE) : []
    languages.any? ? node["class"] = languages.join(" ") : node.remove_attribute("class")
  end

  def scrub_image(img)
    if self.class.pixel?(img)
      @pixels_stripped += 1
      return img.remove
    end
    return img.remove unless img["src"]

    img["src"] = img["src"].sub(/\Ahttp:/, "https:")
    img["referrerpolicy"] = NO_REFERRER
  end

  def scrub_link(link)
    return unless link["href"]

    link["target"] = "_blank"
    link["rel"] = "noopener noreferrer"
  end

  def replace_embed(node)
    url = node["src"] || node.css("source[src]").first&.[]("src")
    row = node.document.create_element("div", class: "r-embed")
    row.add_child(node.document.create_element("span", EMBEDS.fetch(node.name), class: "r-embed-kind"))

    if url
      row.add_child(node.document.create_element("a", "#{url.sub(%r{\Ahttps?://}, "")} ↗",
                                                 href: url, target: "_blank", rel: "noopener noreferrer"))
    else
      row.add_child(node.document.create_element("span", "no source", class: "r-2"))
    end
    node.replace(row)
  end

  # Absolute http(s) URL, or nil.
  def resolve(value)
    uri = @base ? URI.join(@base, value.strip) : URI.parse(value.strip)
    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::Error, ArgumentError
    nil
  end

  # -- 1. Spacers -----------------------------------------------------------

  # Rows whose every cell is blank go before any table is classified, so
  # they never count as rows. A blank cell in a row that has content stays
  # until classification: removing it would shift a data table's columns.
  # Layout tables drop it when they unwrap, data tables when it's blank in
  # every row (#drop_blank_columns).
  def remove_spacers(fragment)
    fragment.css("tr").reverse_each { |row| row.remove if blank?(row) }
    remove_empty_paragraphs(fragment)
  end

  def remove_empty_paragraphs(fragment)
    fragment.css("p").each { |paragraph| paragraph.remove if blank?(paragraph) }
  end

  # No text beyond whitespace, &nbsp; and zero-width characters, and nothing
  # that shows without text (an image, an embed, a rule).
  def blank?(node)
    return whitespace?(node) if node.text?
    return false if SUBSTANCE.include?(node.name) || node.css(SUBSTANCE.join(",")).any?

    node.text.match?(BLANK_TEXT)
  end

  def whitespace?(node)
    (node.text? || node.comment?) && node.text.match?(BLANK_TEXT)
  end

  # -- 2. Tables ------------------------------------------------------------

  # Reverse document order puts every nested table before the table around
  # it, so by the time a table comes up its own nested layout tables are
  # already flat and it's classified on its own rows.
  def resolve_tables(fragment)
    tables = fragment.css("table").to_a
    nested = tables.to_h { |table| [ table, table.css("table").to_a ] }.compare_by_identity
    @tables = tables.size

    tables.reverse_each do |table|
      if data_table?(table, nested[table])
        # A data table inside a data table's cell reads as prose there.
        table.css("table[data-rdr]").each { |inner| unwrap(inner) }
        drop_blank_columns(table)
        table["data-rdr"] = "data"
      else
        unwrap(table)
      end
    end

    fragment.css("table[data-rdr]").each { |table| finish_data_table(table) }
  end

  # RDR-01: no layout table nested inside, no block content (a paragraph,
  # list, image...) in any cell, ≥ 2 rows and ≥ 2 columns with content,
  # and a header (th, thead or caption) or ≥ 3 columns of inline content
  # only; never role=presentation/none. When unsure, layout: unwrapping a
  # data table keeps every word, the reverse turns an article into mono
  # rows.
  def data_table?(table, nested)
    return false if @presentation_tables.include?(table)
    # Nested tables still in the tree were kept as data; any that are gone
    # were layout, and a table holding layout is layout.
    return false if nested.any? { |inner| inner["data-rdr"].nil? }

    rows = own_rows(table).reject { |row| blank?(row) }
    cells = rows.flat_map { |row| own_cells(row) }
    columns = content_columns(rows)
    return false if rows.size < 2 || columns.size < 2
    return false if cells.any? { |cell| block_content?(cell) }

    header?(table) || (columns.size >= 3 && cells.all? { |cell| inline_only?(cell) })
  end

  def own_rows(table)
    table.xpath("./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr").to_a
  end

  def own_cells(row)
    row.xpath("./td | ./th").to_a
  end

  # Indexes of the columns with content in at least one row.
  def content_columns(rows)
    rows.flat_map { |row| own_cells(row).each_index.reject { |index| blank?(own_cells(row)[index]) } }.uniq
  end

  def header?(table)
    table.at_xpath("./caption | ./thead | ./tr/th | ./*/tr/th").present?
  end

  def inline_only?(cell)
    cell.css("*").all? { |element| INLINE.include?(element.name) }
  end

  # A nested (data) table isn't block content here: RDR-01 keeps a data
  # table's cell holding one, and unwraps the inner table instead.
  def block_content?(cell)
    cell.css(BLOCK.join(",")).any? { |block| block.ancestors("table").first == cell.ancestors("table").first }
  end

  def drop_blank_columns(table)
    rows = own_rows(table)
    keep = content_columns(rows)
    rows.each { |row| own_cells(row).each_with_index { |cell, index| cell.remove unless keep.include?(index) } }
  end

  def finish_data_table(table)
    table.css("td").each { |cell| cell["data-num"] = "" if cell.text.strip.match?(NUMERIC_CELL) }
    table.wrap(%(<div class="r-table-scroll"></div>))
  end

  # The table's cells in reading order — row by row, left before right —
  # each a paragraph when it holds only inline content, dissolved into its
  # own blocks otherwise. Glyph cells and blank cells leave nothing.
  def unwrap(table)
    @tables_unwrapped += 1
    blocks = table.xpath("./caption").flat_map { |caption| dissolve(caption) }
    own_rows(table).each do |row|
      own_cells(row).each { |cell| blocks.concat(dissolve(cell)) unless glyph?(cell) }
    end

    blocks.each { |block| table.add_previous_sibling(block) }
    table.remove
  end

  # A cell's children as blocks: each run of inline content becomes one
  # paragraph, block elements stand on their own.
  def dissolve(cell)
    blocks = []
    run = []
    cell.children.each do |child|
      if phrasing?(child)
        run << child
      else
        blocks << build_paragraph(cell.document, run) if run.any?
        blocks << child unless whitespace?(child)
        run = []
      end
    end
    blocks << build_paragraph(cell.document, run) if run.any?
    blocks.compact
  end

  def phrasing?(node)
    node.text? || INLINE.include?(node.name) || node.name == "img"
  end

  # A <p> around the nodes, or nil when they add up to nothing.
  def build_paragraph(document, nodes)
    paragraph = document.create_element("p")
    nodes.each { |node| paragraph.add_child(node) }
    trim_breaks(paragraph)
    paragraph unless blank?(paragraph)
  end

  # A bullet or icon standing alone in its cell: one or two symbol
  # characters, or a single image 24px or smaller.
  def glyph?(cell)
    text = cell.text.delete("\u{fe0f}").gsub(/[\s\u00a0]/, "")
    images = cell.css("img")
    return text.match?(GLYPH) if images.empty?

    text.empty? && images.one? && small_image?(images.first)
  end

  def small_image?(img)
    sizes = IMAGE_ONLY_ATTRIBUTES.filter_map { |name| img[name].to_s[/\A\s*(\d+)(?:px)?\s*\z/, 1]&.to_i }
    sizes.any? && sizes.all? { |size| size <= GLYPH_IMAGE_MAX }
  end

  # -- 3. Paragraph breaks --------------------------------------------------

  # `<br><br>` is how email-era markup separates paragraphs; make them real
  # ones. Loose inline content at the top of the body gets paragraphs too.
  def split_paragraphs(fragment)
    fragment.css("p").each do |paragraph|
      segments = segments(paragraph.children.to_a)
      next trim_breaks(paragraph) if segments.size < 2

      replace_with_paragraphs(paragraph, segments)
    end

    top_level_runs(fragment).each do |run|
      marker = fragment.document.create_text_node("")
      run.first.add_previous_sibling(marker)
      replace_with_paragraphs(marker, segments(run))
    end
    remove_empty_paragraphs(fragment)
  end

  # One paragraph per segment where `node` stands, then `node` goes.
  def replace_with_paragraphs(node, segments)
    segments.each do |nodes|
      paragraph = build_paragraph(node.document, nodes)
      node.add_previous_sibling(paragraph) if paragraph
    end
    node.remove
  end

  # The nodes split wherever two or more `br` meet (whitespace between them
  # allowed); those `br` are dropped. A single `br` stays a line break.
  def segments(nodes)
    segments = [ [] ]
    breaks = []
    nodes.each do |node|
      if node.name == "br" || (breaks.any? && whitespace?(node))
        breaks << node
      else
        close_breaks(breaks, segments)
        segments.last << node
      end
    end
    close_breaks(breaks, segments)
    segments.reject(&:empty?)
  end

  def close_breaks(breaks, segments)
    if breaks.count { |node| node.name == "br" } >= 2
      breaks.each(&:unlink)
      segments << []
    else
      segments.last.concat(breaks)
    end
    breaks.clear
  end

  def top_level_runs(fragment)
    fragment.children.chunk_while { |a, b| phrasing?(a) && phrasing?(b) }
            .select { |run| phrasing?(run.first) && run.any? { |node| !blank?(node) } }
  end

  # `br` (and whitespace) at either end of a paragraph only adds a blank line.
  def trim_breaks(paragraph)
    [ :first, :last ].each do |edge|
      while (node = paragraph.children.public_send(edge)) && (node.name == "br" || whitespace?(node))
        node.unlink
      end
    end
  end

  # -- 4. Rules -------------------------------------------------------------

  # An hr is the only line prose gets, and only one, where the author put
  # it: repeats collapse, and one beside a heading or at either edge of the
  # body goes (the heading's space, or the edge, already divides). Repeats
  # collapse first, so `hr hr h2` loses both rules, not just the second.
  def tidy_rules(fragment)
    fragment.css("hr").each { |hr| hr.remove if neighbour(hr, :previous_sibling)&.name == "hr" }
    fragment.css("hr").each do |hr|
      hr.remove if [ :previous_sibling, :next_sibling ].any? { |direction| HEADINGS.include?(neighbour(hr, direction)&.name) }
    end

    [ :first, :last ].each do |edge|
      while (node = fragment.children.reject { |child| blank?(child) }.public_send(edge))&.name == "hr"
        node.remove
      end
    end
  end

  # The nearest sibling that isn't blank, in one direction.
  def neighbour(node, direction)
    node = node.public_send(direction)
    node = node.public_send(direction) while node && blank?(node)
    node
  end

  # -- 5. Code blocks -------------------------------------------------------

  def frame_code_block(pre)
    code = pre.at_css("code")
    language = [ pre, code ].compact.filter_map { |node| node["class"].to_s[/\b(?:language|lang)-([\w+#-]+)/, 1] }.first
    lines = pre.text.chomp.lines.size
    pre["tabindex"] = "0"

    label = [ "CODE", language, "#{lines} #{lines == 1 ? "line" : "lines"}" ].compact.join(" · ")
    figure = pre.wrap(%(<figure class="r-codeblock"></figure>)).parent
    figure.prepend_child(<<~HTML.squish)
      <div class="r-codeblock-bar"><span>#{ERB::Util.html_escape(label)}</span>
      <button type="button" class="rdr-code-copy" data-action="reader-keys#copyCode"><span class="r-key">C</span> Copy</button></div>
    HTML
  end
end

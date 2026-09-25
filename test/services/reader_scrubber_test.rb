require "test_helper"

class ReaderScrubberTest < ActiveSupport::TestCase
  # Re-parsed from the HTML the reader renders (a Loofah fragment's own
  # #text entity-escapes, which isn't what the page shows).
  def clean(html, base: "https://example.com/posts/1")
    @scrubber = ReaderScrubber.new(base:)
    Nokogiri::HTML5.fragment(@scrubber.clean(html).to_html)
  end

  def words(fragment)
    fragment.xpath(".//text()").map(&:text).join(" ").split
  end

  def blocks(fragment)
    fragment.element_children.map { |node| [ node.name, node.text.squish ] }
  end

  # -- Per node ---------------------------------------------------------------

  test "keeps only language-* classes, and only on pre and code" do
    html = clean(%(<p class="hidden fixed">a</p><pre class="language-ruby hl"><code class="lang-ruby x">b</code></pre>))

    assert_nil html.at_css("p")["class"]
    assert_equal "language-ruby", html.at_css("pre")["class"]
    assert_equal "lang-ruby", html.at_css("code")["class"]
  end

  test "drops attributes outside the list" do
    html = clean(%(<p id="x" style="color:red" onclick="x()" title="t">a</p>))

    assert_equal({ "title" => "t" }, html.at_css("p").to_h)
  end

  test "keeps width and height on images only" do
    html = clean(%(<table width="600" height="20"><tr><th width="50%">A</th><th>B</th></tr><tr><td height="9">1</td><td>2</td></tr></table><img src="/a.png" width="640" height="320">))

    assert_empty html.css("table, th, td").flat_map { |node| node.keys & %w[width height] }
    assert_equal %w[640 320], html.at_css("img").to_h.values_at("width", "height")
  end

  test "resolves relative URLs against the base" do
    html = clean(%(<a href="/about">a</a><img src="img/a.png"><a href="//cdn.example.org/x">b</a>))

    assert_equal "https://example.com/about", html.css("a")[0]["href"]
    assert_equal "https://example.com/posts/img/a.png", html.at_css("img")["src"]
    assert_equal "https://cdn.example.org/x", html.css("a")[1]["href"]
  end

  test "drops URLs that don't resolve to http(s), and images left without one" do
    html = clean(%(<a href="javascript:alert(1)">a</a><a href="mailto:x@example.com">m</a><img src="data:image/png;base64,AAAA">))

    html.css("a").each { |link| assert_nil link["href"] }
    assert_nil html.at_css("img")
  end

  test "leaves relative URLs out when there's no base to resolve them against" do
    html = clean(%(<a href="/about">a</a><a href="https://example.com/x">b</a>), base: nil)

    assert_nil html.css("a")[0]["href"]
    assert_equal "https://example.com/x", html.css("a")[1]["href"]
  end

  test "images load over https without a referrer; links open in a new tab without one" do
    html = clean(%(<img src="http://example.com/a.png"><a href="https://example.com">a</a>))

    assert_equal "https://example.com/a.png", html.at_css("img")["src"]
    assert_equal "no-referrer", html.at_css("img")["referrerpolicy"]
    assert_equal [ "_blank", "noopener noreferrer" ], [ html.at_css("a")["target"], html.at_css("a")["rel"] ]
  end

  test "replaces embeds with a link row" do
    html = clean(<<~HTML)
      <iframe src="https://www.youtube.com/embed/abc"></iframe>
      <video controls><source src="/clip.mp4" type="video/mp4"></video>
      <audio></audio>
    HTML

    rows = html.css(".r-embed")
    assert_equal %w[EMBED VIDEO AUDIO], rows.map { |row| row.at_css(".r-embed-kind").text }
    assert_equal "www.youtube.com/embed/abc ↗", rows[0].at_css("a").text
    assert_equal "https://example.com/clip.mp4", rows[1].at_css("a")["href"]
    assert_equal "no source", rows[2].at_css(".r-2").text
    assert_empty html.css("iframe, video, audio, source")
  end

  test "the per-node scrub alone never lets an iframe through" do
    html = ActionController::Base.helpers.sanitize(%(<iframe src="https://example.com/x"></iframe>), scrubber: ReaderScrubber.new(base: nil))

    assert_no_match(/<iframe/, html)
  end

  test "strips tracking pixels and counts them" do
    html = clean(%(<img src="/t.gif" width="1" height="1"><img src="/s.gif" width="0"><img src="/a.png" width="600" height="1px"><img src="/b.png" width="600">))

    assert_equal [ "https://example.com/b.png" ], html.css("img").map { _1["src"] }
    assert_equal 3, @scrubber.pixels_stripped
  end

  test "removes scripts and styles with their contents" do
    html = clean(%(<p>a</p><script>alert(1)</script><style>p{color:red}</style>))

    assert_equal "a", html.text
  end

  # -- A real newsletter --------------------------------------------------------

  test "Ruby Weekly: all 33 layout tables unwrap into paragraphs, every word kept" do
    source = file_fixture("ruby_weekly_818.html").read
    html = clean(source, base: "https://rubyweekly.com/issues/818")

    assert_equal [ 33, 33 ], [ @scrubber.tables, @scrubber.tables_unwrapped ]
    assert_empty html.css("table, tr, td")
    assert_equal [ "p", "ul" ], html.element_children.map(&:name).uniq.sort
    assert_equal words(Nokogiri::HTML5.fragment(source)), words(html)
  end

  test "Ruby Weekly: a two-column row stacks left before right" do
    html = clean(file_fixture("ruby_weekly_818.html").read, base: "https://rubyweekly.com/issues/818")

    assert_equal [ [ "p", "#​818 — September 24, 2026" ], [ "p", "Read on the Web" ] ], blocks(html).first(2)
  end

  test "Ruby Weekly: no empty paragraphs, the open-tracking pixel counted, the article images kept" do
    html = clean(file_fixture("ruby_weekly_818.html").read, base: "https://rubyweekly.com/issues/818")

    assert html.css("p").none? { |p| p.text.strip.empty? && p.css("img").empty? }
    assert_equal 1, @scrubber.pixels_stripped
    assert_equal 4, html.css("img").size
  end

  # -- Table classification -----------------------------------------------------

  test "a table with a header row and inline cells is data: marked, scrollable, numbers flagged" do
    html = clean(<<~HTML)
      <table><tr><th>File</th><th>Size</th></tr><tr><td>feed.xml</td><td>38.2 kB</td></tr><tr><td>a.png</td><td>1 240</td></tr></table>
    HTML

    table = html.at_css(".r-table-scroll > table[data-rdr=data]")
    assert table
    assert_equal [ "38.2 kB", "1 240" ], table.css("td[data-num]").map(&:text)
    assert_equal [ 1, 0 ], [ @scrubber.tables, @scrubber.tables_unwrapped ]
  end

  test "thead and caption count as a header" do
    html = clean(<<~HTML)
      <table><thead><tr><td>A</td><td>B</td></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>
      <table><caption>Totals</caption><tr><td>A</td><td>B</td></tr><tr><td>1</td><td>2</td></tr></table>
    HTML

    assert_equal 2, html.css("table[data-rdr=data]").size
    assert_equal "Totals", html.at_css("table caption").text
  end

  test "without a header, three or more inline columns make a data table and two don't" do
    html = clean(<<~HTML)
      <table><tr><td>a</td><td>b</td><td>c</td></tr><tr><td>1</td><td><a href="/x">2</a></td><td><em>3</em></td></tr></table>
      <table><tr><td>Left</td><td>Right</td></tr><tr><td>Down</td><td>Up</td></tr></table>
    HTML

    assert_equal 1, html.css("table[data-rdr=data]").size
    assert_equal [ [ "p", "Left" ], [ "p", "Right" ], [ "p", "Down" ], [ "p", "Up" ] ], blocks(html).drop(1)
  end

  test "block content in a cell makes a table layout, header or not" do
    html = clean(<<~HTML)
      <table><tr><th>Name</th><th>Note</th></tr><tr><td>A</td><td><p>Long note.</p></td></tr></table>
    HTML

    assert_empty html.css("table")
    assert_equal [ [ "p", "Name" ], [ "p", "Note" ], [ "p", "A" ], [ "p", "Long note." ] ], blocks(html)
  end

  test "role=presentation or none is always layout" do
    html = clean(<<~HTML)
      <table role="presentation"><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
      <table role="None"><tr><th>C</th><th>D</th></tr><tr><td>3</td><td>4</td></tr></table>
    HTML

    assert_empty html.css("table")
    assert_equal [ 2, 2 ], [ @scrubber.tables, @scrubber.tables_unwrapped ]
  end

  test "one row after spacer removal is layout, even with a th" do
    html = clean(<<~HTML)
      <table><tr><th>Only</th><th>Header</th></tr><tr><td>&nbsp;</td><td><br></td></tr></table>
    HTML

    assert_empty html.css("table")
    assert_equal [ [ "p", "Only" ], [ "p", "Header" ] ], blocks(html)
  end

  test "spacer rows don't count as rows, and a row of only a stripped pixel is a spacer" do
    html = clean(<<~HTML)
      <table>
        <tr><td height="12">&nbsp;</td><td></td></tr>
        <tr><th>A</th><th>B</th></tr>
        <tr><td><img src="/t.gif" width="1" height="1"></td><td> </td></tr>
        <tr><td>1</td><td>2</td></tr>
      </table>
    HTML

    table = html.at_css("table[data-rdr=data]")
    assert_equal 2, table.css("tr").size
    assert_equal 1, @scrubber.pixels_stripped
  end

  test "a column empty in every row is dropped; if that leaves one column the table is layout" do
    html = clean(<<~HTML)
      <table><tr><th>A</th><th></th><th>B</th></tr><tr><td>1</td><td>&nbsp;</td><td>2</td></tr></table>
      <table><tr><th>C</th><th> </th></tr><tr><td>3</td><td></td></tr></table>
    HTML

    table = html.at_css("table[data-rdr=data]")
    assert_equal [ %w[A B], %w[1 2] ], table.css("tr").map { |row| row.css("th, td").map(&:text) }
    assert_equal [ [ "p", "C" ], [ "p", "3" ] ], blocks(html).drop(1)
  end

  test "an empty cell inside a data column stays, so the columns keep their places" do
    html = clean(<<~HTML)
      <table><tr><th>A</th><th>B</th><th>C</th></tr><tr><td>1</td><td></td><td>3</td></tr><tr><td>4</td><td>5</td><td>6</td></tr></table>
    HTML

    assert_equal [ "1", "", "3" ], html.css("table[data-rdr=data] tr")[1].css("td").map(&:text)
  end

  # -- Nesting -----------------------------------------------------------------

  test "nested layout tables flatten in one pass, innermost first" do
    html = clean(<<~HTML)
      <table><tr><td>
        <table><tr><td><table><tr><td><p>Deep</p></td></tr></table></td></tr></table>
        <table><tr><td>Beside</td></tr></table>
      </td></tr></table>
    HTML

    assert_equal [ [ "p", "Deep" ], [ "p", "Beside" ] ], blocks(html)
    assert_equal [ 4, 4 ], [ @scrubber.tables, @scrubber.tables_unwrapped ]
  end

  test "a data table inside a layout cell survives once its wrapper is gone" do
    html = clean(<<~HTML)
      <table><tr><td><p>Intro</p><table><tr><th>K</th><th>V</th></tr><tr><td>a</td><td>1</td></tr></table></td></tr></table>
    HTML

    assert_equal %w[p div], html.element_children.map(&:name)
    assert html.at_css("div.r-table-scroll > table[data-rdr=data]")
    assert_equal [ 2, 1 ], [ @scrubber.tables, @scrubber.tables_unwrapped ]
  end

  test "a table holding a layout table is layout, even with a header" do
    html = clean(<<~HTML)
      <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td><table><tr><td>inner</td></tr></table></td></tr></table>
    HTML

    assert_empty html.css("table")
  end

  test "a data table inside a data table's cell is unwrapped; the outer stays data" do
    html = clean(<<~HTML)
      <table><tr><th>Name</th><th>Detail</th></tr>
        <tr><td>a</td><td><table><tr><th>X</th><th>Y</th></tr><tr><td>1</td><td>2</td></tr></table></td></tr>
      </table>
    HTML

    assert_equal 1, html.css("table").size
    assert html.at_css("table[data-rdr=data]")
    assert_equal %w[X Y 1 2], html.css("table td")[1].css("p").map(&:text)
    assert_equal [ 2, 1 ], [ @scrubber.tables, @scrubber.tables_unwrapped ]
  end

  # -- Unwrapping ---------------------------------------------------------------

  test "an inline cell becomes one paragraph; a block cell dissolves; loose text around blocks gets its own" do
    html = clean(<<~HTML)
      <table><tr><td>Just <strong>text</strong></td></tr><tr><td>Lead <p>Para</p><ul><li>One</li></ul>Tail</td></tr></table>
    HTML

    assert_equal [ [ "p", "Just text" ], [ "p", "Lead" ], [ "p", "Para" ], [ "ul", "One" ], [ "p", "Tail" ] ], blocks(html)
  end

  test "glyph cells in a layout row are dropped: a lone bullet or an icon of 24px or less" do
    html = clean(<<~HTML)
      <table>
        <tr><td>•</td><td>First</td></tr>
        <tr><td>▶️</td><td>Second</td></tr>
        <tr><td><img src="/i.png" width="16" height="16"></td><td>Third</td></tr>
        <tr><td><img src="/photo.png" width="120"></td><td>Fourth</td></tr>
      </table>
    HTML

    assert_equal [ "First", "Second", "Third", "", "Fourth" ], html.element_children.map { |node| node.text.squish }
    assert_equal [ "https://example.com/photo.png" ], html.css("img").map { _1["src"] }
  end

  test "a spacer cell in a layout row leaves nothing behind" do
    html = clean(<<~HTML)
      <table><tr><td width="20">&nbsp;<br></td><td>Text</td><td><img src="/p.gif" width="1" height="1"></td></tr></table>
    HTML

    assert_equal [ [ "p", "Text" ] ], blocks(html)
  end

  test "a layout-only newsletter leaves no table markup for the table rules to style" do
    html = clean(<<~HTML)
      <table width="600" bgcolor="#eee" style="border:1px solid"><tr><td>
        <table role="presentation"><tr><td>•</td><td><a href="/a">Story</a> — summary</td></tr></table>
        <hr><hr>
        <table><tr><td bgcolor="#ffc"><strong>Sponsor</strong><br><br>Copy</td></tr></table>
      </td></tr></table>
    HTML

    assert_empty html.css("table, thead, tbody, tr, td, th, [style], [bgcolor], [width]")
    assert_equal [ [ "p", "Story — summary" ], [ "hr", "" ], [ "p", "Sponsor" ], [ "p", "Copy" ] ], blocks(html)
  end

  test "empty paragraphs go" do
    html = clean(%(<p>&nbsp;</p><p><br></p><p>Kept</p><p> <span></span> </p>))

    assert_equal [ [ "p", "Kept" ] ], blocks(html)
  end

  # -- Paragraph breaks ---------------------------------------------------------

  test "two or more br split a paragraph; a single br stays a line break" do
    html = clean(%(<p>One<br>still one<br><br>Two<br> <br><br>Three<br></p>))

    assert_equal [ "One<br>still one", "Two", "Three" ], html.css("p").map(&:inner_html)
  end

  test "loose text at the top of the body becomes paragraphs, split the same way" do
    html = clean(%(First line<br><br>Second <a href="/x">line</a><blockquote>Quote</blockquote>After))

    assert_equal [ [ "p", "First line" ], [ "p", "Second line" ], [ "blockquote", "Quote" ], [ "p", "After" ] ], blocks(html)
  end

  # -- Rules --------------------------------------------------------------------

  test "consecutive hrs collapse to one, even with empty elements between" do
    html = clean(%(<p>A</p><hr><hr><p>&nbsp;</p><hr><p>B</p>))

    assert_equal %w[p hr p], html.element_children.map(&:name)
  end

  test "an hr beside a heading goes, on either side" do
    html = clean(%(<p>A</p><hr><h2>Next</h2><hr><p>B</p><hr><hr><h3>Last</h3><p>C</p>))

    assert_equal %w[p h2 p h3 p], html.element_children.map(&:name)
  end

  test "an hr at either edge of the body goes" do
    html = clean(%(<hr><hr><p>A</p><hr><p>B</p><hr><p> </p>))

    assert_equal %w[p hr p], html.element_children.map(&:name)
  end

  test "a newsletter's divider rows unwrap to one rule between sections" do
    html = clean(<<~HTML)
      <table><tr><td><p>Intro</p></td></tr><tr><td><hr></td></tr><tr><td>&nbsp;</td></tr><tr><td><hr></td></tr><tr><td><p>Story</p></td></tr></table>
    HTML

    assert_equal %w[p hr p], html.element_children.map(&:name)
  end

  # -- Code blocks --------------------------------------------------------------

  test "pre is framed as a code block with a label bar" do
    html = clean(%(<pre class="language-ruby"><code>puts 1\nputs 2</code></pre><pre>x</pre>))

    frames = html.css("figure.r-codeblock")
    assert_equal [ "CODE · ruby · 2 lines", "CODE · 1 line" ], frames.map { |frame| frame.at_css(".r-codeblock-bar > span").text }
    assert frames.all? { |frame| frame.at_css("> pre[tabindex='0']") && frame.at_css(".rdr-code-copy") }
  end
end

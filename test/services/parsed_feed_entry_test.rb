require "test_helper"

class ParsedFeedEntryTest < ActiveSupport::TestCase
  def rss_entry(item_xml)
    xml = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <channel><title>t</title><link>https://example.com</link><description>d</description>
          <item><title>i</title><link>https://example.com/i</link>#{item_xml}</item>
        </channel>
      </rss>
    XML
    ParsedFeed.parse_xml(xml).entries.first
  end

  def atom_entry(entry_xml)
    xml = <<~XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><id>f</id><updated>2026-09-24T00:00:00Z</updated>
        <entry><title>e</title><id>1</id><updated>2026-09-24T00:00:00Z</updated>#{entry_xml}</entry>
      </feed>
    XML
    ParsedFeed.parse_xml(xml).entries.first
  end

  test "RSS content:encoded is full content, preferred over the description" do
    entry = rss_entry("<description>short</description><content:encoded><![CDATA[<p>full</p>]]></content:encoded>")

    assert_equal [ "<p>full</p>", "full", "content:encoded" ], [ entry.body.html, entry.body.kind, entry.body.source ]
  end

  test "an RSS description alone is an excerpt" do
    entry = rss_entry("<description>short</description>")

    assert_equal [ "short", "excerpt", "description" ], [ entry.body.html, entry.body.kind, entry.body.source ]
  end

  test "Atom content is full content, preferred over the summary" do
    entry = atom_entry(%(<summary>s</summary><content type="html">&lt;p&gt;c&lt;/p&gt;</content>))

    assert_equal [ "<p>c</p>", "full", "content" ], [ entry.body.html, entry.body.kind, entry.body.source ]
  end

  test "an Atom summary alone is an excerpt" do
    entry = atom_entry("<summary>s</summary>")

    assert_equal [ "s", "excerpt", "summary" ], [ entry.body.html, entry.body.kind, entry.body.source ]
  end

  test "an entry with no content fields is empty" do
    assert_equal "empty", rss_entry("").body.kind
    assert_equal "empty", atom_entry("").body.kind
    assert_nil rss_entry("").body.html
  end

  test "author comes from Atom <author><name>, RSS dc:creator, then RSS author" do
    assert_equal "Ann", atom_entry("<author><name>Ann</name></author>").author
    assert_equal "Jane", rss_entry("<dc:creator>Jane</dc:creator><author>bob@example.com (Bob)</author>").author
    assert_equal "bob@example.com (Bob)", rss_entry("<author>bob@example.com (Bob)</author>").author
    assert_nil rss_entry("").author
  end
end

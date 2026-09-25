require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @item = items(:one)
  end

  test "should get index" do
    get items_url
    assert_response :success
  end

  test "should get new" do
    get new_item_url
    assert_response :success
  end

  test "should create item" do
    assert_difference("Item.count") do
      post items_url, params: { item: { feed_id: @item.feed_id, summary: @item.summary, link: @item.link, title: @item.title } }
    end

    assert_redirected_to item_url(Item.last)
    assert_equal @item.feed, Item.last.feed
  end

  test "create refuses another user's feed" do
    assert_no_difference("Item.count") do
      post items_url, params: { item: { feed_id: feeds(:two).id, title: "Planted" } }
    end

    assert_response :not_found
  end

  test "should show item" do
    get item_url(@item)
    assert_response :success
  end

  test "showing an item marks it read without affecting other items" do
    other_item = items(:two)
    assert_not @item.read?
    assert_not other_item.read?

    get item_url(@item)

    assert @item.reload.read?
    assert_not other_item.reload.read?
  end

  test "show sanitizes item summary instead of rendering it raw" do
    @item.update!(summary: "<script>alert('xss')</script><p>safe</p>")

    get item_url(@item)

    assert_response :success
    assert_no_match "<script>", response.body
    assert_match "<p>safe</p>", response.body
  end

  test "show keeps table markup instead of stripping it like Rails' sanitize default" do
    @item.update!(summary: "<table><tr><th>Key</th><th>Value</th></tr><tr><td>cell</td><td>1</td></tr></table>")

    get item_url(@item)

    assert_response :success
    assert_match %(<table data-rdr="data">), response.body
    assert_match "<td>cell</td>", response.body
  end

  test "show still strips tags outside the reading-surface allow-list" do
    @item.update!(summary: "<script>alert('xss')</script><marquee>ok</marquee><p>safe</p>")

    get item_url(@item)

    assert_response :success
    assert_no_match "<script>", response.body
    assert_no_match "<marquee>", response.body
    assert_match "<p>safe</p>", response.body
  end

  test "show only links item.link when it is a safe http(s) url" do
    @item.update!(link: "javascript:alert('xss')")

    get item_url(@item)

    assert_response :success
    assert_no_match "javascript:alert", response.body
  end

  test "show links item.link when it is a safe http(s) url" do
    @item.update!(link: "https://example.com/post")

    get item_url(@item)

    assert_response :success
    assert_match %(href="https://example.com/post"), response.body
  end

  test "should get edit" do
    get edit_item_url(@item)
    assert_response :success
  end

  test "should update item" do
    patch item_url(@item), params: { item: { summary: @item.summary, link: @item.link, title: @item.title } }
    assert_redirected_to item_url(@item)
  end

  test "should destroy item" do
    assert_difference("Item.count", -1) do
      delete item_url(@item)
    end

    assert_redirected_to items_url
  end

  test "loaded as its own URL, show renders the whole app with the item's feed listed and the item open" do
    get item_url(@item)

    assert_select ".rdr-panes[data-screen=reader]"
    assert_select "#feeds"
    assert_select "#current_feed #items tr#item_#{@item.id}"
    assert_select "#current_item .rdr-reader[data-item-id='#{@item.id}']"
  end

  test "inside the reader frame, show renders just the frame" do
    get item_url(@item), headers: { "Turbo-Frame" => "current_item" }

    assert_select "#current_item .rdr-reader"
    assert_select "#feeds", count: 0
  end

  test "show states an excerpt and offers the rest on the publisher's site" do
    @item.update!(content_kind: "excerpt", content_source: "description", link: "https://example.com/post", summary: "<p>Just the start</p>")

    get item_url(@item)

    assert_select ".rdr-notice", text: /EXCERPT\s+This feed sends <description> only/
    assert_select ".rdr-endbox a[href='https://example.com/post']", text: /CONTINUE ON example.com/
  end

  test "show says when the feed sent no content at all" do
    @item.update!(content_kind: "empty", content_source: nil, summary: nil, link: "https://example.com/post")

    get item_url(@item)

    assert_select ".rdr-notice", text: /EMPTY/
    assert_select ".rdr-endbox", text: /NO CONTENT IN FEED/
    assert_select ".r-body", count: 0
  end

  test "the details CONTENT row counts unwrapped tables next to the stripped pixels" do
    @item.update!(summary: <<~HTML)
      <table><tr><td><table><tr><td>Layout</td></tr></table></td></tr></table>
      <table><tr><th>K</th><th>V</th></tr><tr><td>a</td><td>1</td></tr></table>
      <img src="https://example.com/t.gif" width="1" height="1">
    HTML

    get item_url(@item)

    assert_select ".rdr-details-grid dd", text: /· 1 pixel stripped · 2 of 3 tables unwrapped/
  end

  test "show applies the user's text size, measure and details setting" do
    users(:one).update!(reader_text_size: 19, reader_measure: 76, reader_details_expanded: false)

    get item_url(@item)

    assert_select ".rdr-reader[data-details-expanded=false][style*='--reader-size: 19px'][style*='--reader-measure: 76ch']"
  end

  test "show shapes the body: demoted headings, lazy images, labelled code blocks, data tables" do
    @item.update!(summary: <<~HTML)
      <h1>Top</h1><h5>Deep</h5><img src="https://example.com/a.png">
      <pre class="language-ruby"><code>puts 1
      puts 2</code></pre>
      <table><tr><th>File</th><th>Size</th></tr><tr><td>feed.xml</td><td>38.2 kB</td></tr></table>
    HTML

    get item_url(@item)

    assert_select ".r-body h1", count: 0
    assert_select ".r-body h2", text: "Top"
    assert_select ".r-body h3", text: "Deep"
    assert_select ".r-body img[loading=lazy]"
    assert_select ".r-body .r-codeblock .r-codeblock-bar", text: /CODE · ruby · 2 lines/
    assert_select ".r-body .r-table-scroll table[data-rdr=data] td[data-num]", text: "38.2 kB"
  end

  test "details count the tracking pixels the reader stripped" do
    @item.update!(summary: %(<p>Hi</p><img src="https://example.com/t.gif" width="1" height="1">))

    get item_url(@item)

    assert_select ".rdr-details-grid dd", text: /1 pixel stripped/
    assert_select ".r-body img", count: 0
  end

  test "details count the layout tables the reader unwrapped" do
    @item.update!(summary: <<~HTML)
      <table><tr><td><p>Hi</p></td></tr></table>
      <table><tr><th>File</th><th>Size</th></tr><tr><td>feed.xml</td><td>38.2 kB</td></tr></table>
    HTML

    get item_url(@item)

    assert_select ".rdr-details-grid dd", text: /1 of 2 tables unwrapped/
    assert_select ".r-body table", count: 1
  end

  test "first_unread opens the newest unread item" do
    @item.update!(published_at: 1.hour.ago)
    newer = feeds(:one).items.create!(title: "Newer", link: "https://example.com/n", published_at: 1.minute.ago)

    get first_unread_items_url

    assert_redirected_to feed_item_url(newer.feed, newer)
  end

  test "first_unread goes home when nothing is unread" do
    users(:one).items.update_all(read: true)

    get first_unread_items_url

    assert_redirected_to root_url
  end

  test "an item opens within a group: that river listed, Groups mode, back links to the group" do
    feeds(:one).update!(folder: folders(:tech))

    get group_item_url(folders(:tech), @item)

    assert_select ".rdr-panes[data-screen=reader]"
    assert_select ".rdr-pane-tree[data-tree-mode=groups]"
    assert_select "#items[data-tree-row=group_#{folders(:tech).id}][data-list-kind=group][data-list-name=Tech]"
    assert_select "#items[data-item-path='#{group_item_path(folders(:tech), "ITEM_ID")}']"
    assert_select "#item_#{@item.id} .r-title a[href='#{group_item_path(folders(:tech), @item)}']"
    assert_select ".rdr-reader a.rdr-back[href='#{group_path(folders(:tech))}']"
    assert_select ".rdr-reader [data-reader-position=narrow]", text: "Tech"
    assert @item.reload.read?
  end

  test "an item opens within All feeds, its feed (Feeds mode), or Marked" do
    get group_item_url("all", @item)
    assert_select "#items[data-tree-row=group_all]"

    get feed_item_url(@item.feed, @item)
    assert_select ".rdr-pane-tree[data-tree-mode=feeds]"
    assert_select "#items[data-tree-row=feed_#{@item.feed_id}][data-list-kind=feed]"

    @item.update!(marked: true)
    get marked_item_url(@item)
    assert_select "#items[data-tree-row=marked_view][data-list-kind=marked]"
    assert_select ".rdr-reader a.rdr-back[href='#{marked_items_path}']"
  end

  test "an item outside the list its URL names is not found there" do
    other_feed = users(:one).feeds.create!(title: "Other", link: "https://o.example.com", feed_url: "https://o.example.com/rss")

    get feed_item_url(other_feed, @item)
    assert_response :not_found

    get group_item_url("ungrouped", @item.tap { @item.feed.update!(folder: folders(:tech)) })
    assert_response :not_found
    assert_not @item.reload.read?
  end

  test "inside the reader frame, a scoped item renders just the reader with the list's back link" do
    get group_item_url("all", @item), headers: { "Turbo-Frame" => "current_item" }

    assert_select ".rdr-panes", count: 0
    assert_select ".rdr-reader a.rdr-back[href='#{group_path("all")}']"
  end
end

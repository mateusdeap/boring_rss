require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "create re-renders the dialog with a field error for an invalid feed" do
    assert_no_difference("Feed.count") do
      post feeds_url, params: { feed: { link: "this is not xml or a url" } }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_match "Couldn&#39;t find a feed at that address.", response.body
  end

  test "create accepts an Atom feed missing a feed-level author tag" do
    # Real, reproduced bug: RSS::Parser's default strict validation rejects
    # this — https://37signals.com/feed/jobs.xml is a live example — even
    # though the feed is otherwise complete and functional. `normalize_rss`
    # (rss gem) treats any string containing "<" as inline XML rather than
    # a URL, so this hits the exact same parse path with no network call.
    atom_feed = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Jobs</title>
        <id>tag:example.com,2026:jobs</id>
        <updated>2026-01-01T00:00:00Z</updated>
        <link href="https://example.com/jobs/"/>
      </feed>
    XML

    assert_difference("Feed.count") do
      post feeds_url, params: { feed: { link: atom_feed } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "Jobs", Feed.last.title
  end

  test "create files the new feed in the named folder" do
    atom_feed = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Jobs</title>
        <id>tag:example.com,2026:jobs</id>
        <updated>2026-01-01T00:00:00Z</updated>
        <link href="https://example.com/jobs/"/>
      </feed>
    XML

    post feeds_url, params: { feed: { link: atom_feed, folder_name: "Tech" } }, as: :turbo_stream

    assert_response :success
    assert_equal folders(:tech), Feed.last.folder
    assert_match %(<turbo-stream action="replace" target="folder-names">), response.body
  end

  test "index renders folders with their feeds under them" do
    feeds(:one).update!(folder: folders(:tech))

    get feeds_url

    assert_response :success
    assert_select "#feeds li#folder_#{folders(:tech).id}[role=treeitem][aria-expanded=true]"
    assert_select "#feeds li#feed_#{feeds(:one).id}.r-child[data-parent-folder='#{folders(:tech).id}']"
    assert_select "#feeds li#folder_#{folders(:other_users).id}", count: 0
  end

  test "children of a collapsed folder render hidden" do
    folders(:tech).update!(collapsed: true)
    feeds(:one).update!(folder: folders(:tech))

    get feeds_url

    assert_select "#feeds li#folder_#{folders(:tech).id}[aria-expanded=false]"
    assert_select "#feeds li#feed_#{feeds(:one).id}[hidden]"
  end

  test "move files a feed into a folder by name, creating it if needed" do
    assert_difference -> { users(:one).folders.count } do
      patch feed_url(feeds(:one)), params: { feed: { folder_name: "Reading" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "Reading", feeds(:one).reload.folder.name
    assert_match %(<turbo-stream action="update" target="feeds">), response.body
  end

  test "move with a blank folder name returns the feed to the top level" do
    feeds(:one).update!(folder: folders(:tech))

    patch feed_url(feeds(:one)), params: { feed: { folder_name: "" } }, as: :turbo_stream

    assert_nil feeds(:one).reload.folder_id
  end

  test "another user's feed can't be moved" do
    patch feed_url(feeds(:two)), params: { feed: { folder_name: "Mine" } }, as: :turbo_stream

    assert_response :not_found
    assert_nil feeds(:two).reload.folder_id
  end

  test "show lists only unread items when the user's filter is on" do
    feed = feeds(:one)
    read_item = feed.items.create!(title: "Already read", link: "https://example.com/r", read: true)
    unread_item = feed.items.create!(title: "Still unread", link: "https://example.com/u")

    get feed_url(feed)
    assert_select "tr#item_#{read_item.id}"

    users(:one).update!(unread_only: true)
    get feed_url(feed)
    assert_select "tr#item_#{read_item.id}", count: 0
    assert_select "tr#item_#{unread_item.id}"
    assert_select "button[aria-pressed=true][data-shortcut='shift+u']"
  end

  test "mark all read is disabled with its reason when nothing is unread" do
    feeds(:one).items.update_all(read: true)

    get feed_url(feeds(:one))

    assert_select "button[disabled]", text: /Mark all read — none unread/
  end

  test "the Marked row sits under both modes' lists, with its count" do
    items(:one).update!(marked: true)

    get feeds_url

    assert_select ".rdr-pane-tree > .rdr-pane-scroll > ul:last-child > li#marked_view .rdr-count-mark", text: "1"
  end

  test "the left pane opens in the user's mode, Groups by default, with both lists rendered" do
    get feeds_url

    assert_select ".rdr-pane-tree[data-tree-mode=groups]"
    assert_select "[data-tree-mode-button=groups][aria-pressed=true]", text: /G\s+Groups/
    assert_select "[data-tree-mode-button=feeds][aria-pressed=false]", text: /F\s+Feeds/
    assert_select "#groups li"
    assert_select "#feeds li"

    users(:one).update!(tree_mode: "feeds")
    get feeds_url

    assert_select ".rdr-pane-tree[data-tree-mode=feeds]"
  end

  test "Groups mode lists All feeds first, then folders, then Ungrouped" do
    feeds(:one).update!(folder: folders(:tech))
    users(:one).feeds.create!(title: "Loose", link: "https://loose.example.com", feed_url: "https://loose.example.com/rss")

    get feeds_url

    assert_equal [ "group_all", "group_#{folders(:tech).id}", "group_ungrouped" ], css_select("#groups > li").map { _1["id"] }
    assert_select "#groups > li.r-group.r-all:first-child .r-name", text: "All feeds"
  end

  test "a group's failing health links to that feed" do
    feeds(:one).update!(folder: folders(:tech), last_fetched_at: Time.current, last_fetch_error_at: Time.current, last_fetch_status: "503")

    get feeds_url

    assert_select "#group_#{folders(:tech).id} a.r-health[href='#{feed_path(feeds(:one))}'] .r-code-fail", text: "1 ERR"
    assert_select "#group_all a.r-health .r-code-fail", text: "1 ERR"
  end

  test "a feed page opens the left pane in Feeds mode" do
    get feed_url(feeds(:one))

    assert_select ".rdr-pane-tree[data-tree-mode=feeds]"
  end

  test "loaded as its own URL, show renders the whole app on the items screen" do
    get feed_url(feeds(:one))

    assert_select ".rdr-panes[data-screen=items]"
    assert_select "#current_feed #items[data-tree-row=feed_#{feeds(:one).id}]"
    assert_select "#current_item", text: /No item selected/
  end

  test "index shows the unread count and the first-unread action when nothing is open" do
    get feeds_url

    assert_select ".rdr-panes[data-screen=feeds]"
    assert_select "#current_item", text: /1 unread in 1 feed/
    assert_select "a[data-open-first-unread][href='#{first_unread_items_path}']"
  end

  test "index offers to poll now when nothing is unread" do
    users(:one).items.update_all(read: true)

    get feeds_url

    assert_select "#current_item form[action='#{poll_path}'] button[data-reader-key=r]", text: /Poll now/
  end
end

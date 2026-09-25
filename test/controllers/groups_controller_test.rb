require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    feeds(:one).update!(folder: folders(:tech))
    @loose = users(:one).feeds.create!(title: "Loose", link: "https://loose.example.com", feed_url: "https://loose.example.com/rss")
    @loose_item = @loose.items.create!(title: "Loose item", published_at: 1.minute.ago)
    @loose.refresh_volume!
  end

  test "All feeds merges every feed's items, newest first, with a Feed column" do
    get group_url("all")

    assert_select ".rdr-panes[data-screen=items]"
    assert_select ".rdr-pane-tree[data-tree-mode=groups]"
    assert_select "#current_feed .r-panel-h", text: /02 ITEMS — All feeds/
    assert_select "#items[data-tree-row=group_all] > tr", count: users(:one).items.count
    assert_select "#items > tr:first-child .r-title", text: "Loose item"
    assert_select "#current_feed thead th", text: "Feed"
  end

  test "a folder's river holds only its feeds' items" do
    get group_url(folders(:tech))

    assert_select "#items[data-tree-row=group_#{folders(:tech).id}] > tr", count: feeds(:one).items.count
  end

  test "Ungrouped holds the feeds with no folder" do
    get group_url("ungrouped")

    assert_select "#items > tr", count: 1
    assert_select "#items .r-title", text: "Loose item"
  end

  test "inside the frame, only the list renders" do
    get group_url("all"), headers: { "Turbo-Frame" => "current_feed" }

    assert_select "turbo-frame#current_feed"
    assert_select ".rdr-panes", count: 0
  end

  test "another user's folder is not found" do
    get group_url(folders(:other_users))

    assert_response :not_found
  end

  test "the source column is FEED in a river and AUTHOR in one feed; every list shows words" do
    get group_url("all")
    assert_select "table.rdr-source-feed thead th", text: "Feed"
    assert_select "table.rdr-source-feed thead th", text: "Words"
    assert_select "#item_#{@loose_item.id} td.r-feed", text: "Loose"

    get feed_url(@loose)
    assert_select "table.rdr-source-author thead th", text: "Author"
  end

  test "a river lists its feeds in data-feed-ids so new items find it" do
    get group_url("ungrouped")

    assert_select "#items[data-sort=time][data-feed-ids='#{@loose.id}']"
  end

  test "S sorts by feed: one header per feed with unread, volume and health, items under it" do
    patch group_sort_url("all"), params: { sort: "feed" }
    assert_redirected_to group_path("all")
    assert_equal "feed", users(:one).reload.item_sort(Group.find(users(:one), "all"))

    get group_url("all")

    assert_select "#items[data-sort=feed]"
    assert_select "tr.r-feedhead", count: 2
    assert_select "tr#feedhead_#{@loose.id} + tr#item_#{@loose_item.id}"
    assert_select "tr#feedhead_#{@loose.id}", text: /Loose\s+· 1 unread · <1 item \/ wk/
    assert_select "[data-shortcut=s][aria-pressed=false]", text: /Time/
    assert_select ".r-panel-h .r-label", text: /sort feed/
  end

  test "the sort is remembered per group, and an unknown sort is ignored" do
    patch group_sort_url("all"), params: { sort: "feed" }
    patch group_sort_url("ungrouped"), params: { sort: "bogus" }

    user = users(:one).reload
    assert_equal "feed", user.item_sort(Group.find(user, "all"))
    assert_equal "time", user.item_sort(Group.find(user, "ungrouped"))
  end

  test "⇧R marks the whole river read, and only that river" do
    other = feeds(:one).items.create!(title: "Filed item")

    post group_reading_url("ungrouped")

    assert_redirected_to group_path("ungrouped")
    assert @loose_item.reload.read?
    assert_not other.reload.read?
  end
end

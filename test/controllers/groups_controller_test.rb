require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    feeds(:one).update!(folder: folders(:tech))
    @loose = users(:one).feeds.create!(title: "Loose", link: "https://loose.example.com", feed_url: "https://loose.example.com/rss")
    @loose_item = @loose.items.create!(title: "Loose item", published_at: 1.minute.ago)
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
end

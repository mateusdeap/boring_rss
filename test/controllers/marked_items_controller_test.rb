require "test_helper"

class MarkedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "lists the user's marked items across feeds, with their feed" do
    other_feed = users(:one).feeds.create!(title: "Second feed", link: "https://example.com/2", feed_url: "https://example.com/2.xml")
    marked_here = items(:one).tap { |item| item.update!(marked: true) }
    marked_there = other_feed.items.create!(title: "Over there", link: "https://example.com/o", marked: true)
    not_marked = feeds(:one).items.create!(title: "Plain", link: "https://example.com/p")

    get marked_items_url

    assert_response :success
    assert_select "tbody#items[data-tree-row=marked_view]"
    assert_select "tr#item_#{marked_here.id}.is-marked"
    assert_select "tr#item_#{marked_there.id} td.r-feed", text: "Second feed"
    assert_select "tr#item_#{not_marked.id}", count: 0
  end

  test "never shows another user's marked items" do
    items(:two).update!(marked: true)

    get marked_items_url

    assert_select "tr#item_#{items(:two).id}", count: 0
    assert_select "p.r-empty", text: /No marked items/
  end
end

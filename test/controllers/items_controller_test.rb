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
      post items_url, params: { item: { summary: @item.summary, link: @item.link, title: @item.title } }
    end

    assert_redirected_to item_url(Item.last)
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
    @item.update!(summary: "<table><tr><td>cell</td></tr></table>")

    get item_url(@item)

    assert_response :success
    assert_match "<table>", response.body
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
end

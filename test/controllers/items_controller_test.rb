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

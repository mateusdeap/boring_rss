require "test_helper"

class Items::MarksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @item = items(:one)
  end

  test "create marks the item and re-renders its row and the reader button" do
    post item_mark_url(@item), as: :turbo_stream

    assert_response :success
    assert @item.reload.marked?
    assert_match %(target="#{ActionView::RecordIdentifier.dom_id(@item)}"), response.body
    assert_match %(target="#{ActionView::RecordIdentifier.dom_id(@item, :mark)}"), response.body
    assert_match "is-marked", response.body
    assert_match %(target="marked_view"), response.body
  end

  test "destroy unmarks the item" do
    @item.update!(marked: true)

    delete item_mark_url(@item), as: :turbo_stream

    assert_response :success
    assert_not @item.reload.marked?
  end

  test "marking does not mark the item read" do
    post item_mark_url(@item), as: :turbo_stream

    assert_not @item.reload.read?
  end

  test "another user's item is not found" do
    post item_mark_url(items(:two)), as: :turbo_stream

    assert_response :not_found
    assert_not items(:two).reload.marked?
  end
end

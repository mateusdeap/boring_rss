require "test_helper"

class Items::ReadingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @item = items(:one)
  end

  test "destroy marks the item unread and re-renders its row and the reader button" do
    @item.update!(read: true)

    delete item_reading_url(@item), as: :turbo_stream

    assert_response :success
    assert_not @item.reload.read?
    assert_match %(target="#{ActionView::RecordIdentifier.dom_id(@item)}"), response.body
    assert_match %(target="#{ActionView::RecordIdentifier.dom_id(@item, :reading)}"), response.body
    assert_match "is-unread", response.body
  end

  test "create marks the item read again" do
    post item_reading_url(@item), as: :turbo_stream

    assert_response :success
    assert @item.reload.read?
  end

  test "can't touch another user's item" do
    delete item_reading_url(items(:two)), as: :turbo_stream

    assert_response :not_found
  end
end

require "test_helper"

class FoldersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @folder = folders(:tech)
  end

  test "rename re-renders the tree" do
    patch folder_url(@folder), params: { folder: { name: "Hardware" } }, as: :turbo_stream

    assert_response :success
    assert_equal "Hardware", @folder.reload.name
    assert_match %(<turbo-stream action="update" target="feeds">), response.body
  end

  test "rename to a taken name reports the error in the dialog" do
    users(:one).folders.create!(name: "Taken")

    patch folder_url(@folder), params: { folder: { name: "Taken" } }, as: :turbo_stream

    assert_response :unprocessable_content
    assert_match "rename-folder-error", response.body
    assert_match "ERR Name has already been taken", response.body
  end

  test "collapse toggle saves the state" do
    patch folder_url(@folder), params: { folder: { collapsed: true } }, as: :json

    assert_response :no_content
    assert @folder.reload.collapsed?
  end

  test "destroy moves the folder's feeds to the top level" do
    feeds(:one).update!(folder: @folder)

    delete folder_url(@folder), as: :turbo_stream

    assert_response :success
    assert_not Folder.exists?(@folder.id)
    assert_nil feeds(:one).reload.folder_id
  end

  test "another user's folder is not found" do
    patch folder_url(folders(:other_users)), params: { folder: { name: "Mine now" } }, as: :turbo_stream
    assert_response :not_found

    delete folder_url(folders(:other_users)), as: :turbo_stream
    assert_response :not_found
    assert Folder.exists?(folders(:other_users).id)
  end
end

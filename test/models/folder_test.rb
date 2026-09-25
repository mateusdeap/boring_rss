require "test_helper"

class FolderTest < ActiveSupport::TestCase
  test "names are squished and unique per user, not globally" do
    folder = users(:one).folders.create!(name: "  Ruby   and Rails ")
    assert_equal "Ruby and Rails", folder.name

    assert_not users(:one).folders.build(name: "Tech").valid?
    assert users(:two).folders.build(name: "Tech").valid?
  end

  test "unread_count sums unread items across its feeds" do
    folder = folders(:tech)
    feeds(:one).update!(folder:)
    feeds(:one).items.update_all(read: false)

    assert_equal feeds(:one).items.count, folder.unread_count
  end

  test "destroying a folder moves its feeds to the top level" do
    folder = folders(:tech)
    feeds(:one).update!(folder:)

    folder.destroy!

    assert_nil feeds(:one).reload.folder_id
  end

  test "feed folder_name= files by name, creating the folder for the feed's owner" do
    feed = feeds(:one)

    feed.update!(folder_name: "Tech")
    assert_equal folders(:tech), feed.folder

    assert_difference -> { users(:one).folders.count } do
      feed.update!(folder_name: "New one")
    end

    feed.update!(folder_name: " ")
    assert_nil feed.folder
  end

  test "a feed can't be filed in another user's folder" do
    feed = feeds(:one)
    feed.folder = folders(:other_users)

    assert_not feed.valid?
  end

  test "a filed feed's row broadcast also re-renders its folder row and the group rows showing it" do
    feed = feeds(:one)
    feed.update!(folder: folders(:tech))

    streams = capture_turbo_stream_broadcasts([ feed.user, :feeds ]) { feed.broadcast_row }

    assert_equal [ "feed_#{feed.id}", "folder_#{folders(:tech).id}", "group_all", "group_#{folders(:tech).id}" ],
                 streams.map { |stream| stream["target"] }
  end
end

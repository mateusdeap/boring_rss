require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "unread scope returns only unread items" do
    read_item = items(:one)
    read_item.update!(read: true)

    assert_includes Item.unread, items(:two)
    assert_not_includes Item.unread, read_item
  end

  test "new items default to unread" do
    item = Item.create!(feed: feeds(:one), title: "t", link: "l")
    assert_not item.read?
  end

  test "creating an item broadcasts a feed row replace to the owner's feeds stream only" do
    feed = feeds(:one)

    assert_no_turbo_stream_broadcasts :feeds do
      assert_turbo_stream_broadcasts [ feed.user, :feeds ] do
        Item.create!(feed:, title: "t", link: "l")
      end
    end
  end

  test "mark_read! flips read to true and enqueues broadcasts" do
    item = items(:one)
    assert_not item.read?

    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      item.mark_read!
    end

    assert item.reload.read?
  end

  test "mark_read! is a no-op when already read" do
    item = items(:one)
    item.update!(read: true)

    assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
      item.mark_read!
    end
  end
end

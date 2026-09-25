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

  test "counts words, images and links when the body is saved" do
    item = Item.create!(feed: feeds(:one), title: "t", link: "l",
                        summary: %(<p>Three short words <a href="https://example.com">here</a></p><img src="a.png"><img src="b.png">))

    assert_equal [ 4, 2, 1 ], [ item.word_count, item.image_count, item.link_count ]
  end

  test "tracking pixels don't count as images" do
    item = Item.create!(feed: feeds(:one), title: "t", link: "l", summary: %(<img src="a.png"><img src="t.gif" width="1" height="1">))

    assert_equal 1, item.image_count
  end

  test "reading_minutes is the word count at 200 wpm, at least a minute for any words" do
    assert_equal 0, Item.new(word_count: 0).reading_minutes
    assert_equal 1, Item.new(word_count: 20).reading_minutes
    assert_equal 6, Item.new(word_count: 1240).reading_minutes
  end

  test "mark_unread! flips read to false and enqueues broadcasts" do
    item = items(:one)
    item.update!(read: true)

    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      item.mark_unread!
    end

    assert_not item.reload.read?
  end

  test "mark_unread! is a no-op when already unread" do
    assert_no_enqueued_jobs do
      items(:one).mark_unread!
    end
  end
end

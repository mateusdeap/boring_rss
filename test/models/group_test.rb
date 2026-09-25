require "test_helper"

class GroupTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @filed = feeds(:one)
    @filed.update!(folder: folders(:tech))
    @loose = @user.feeds.create!(title: "Loose", link: "https://loose.example.com", feed_url: "https://loose.example.com/rss")
  end

  test "for lists All feeds, each folder, then Ungrouped" do
    assert_equal [ "all", folders(:tech).id.to_s, "ungrouped" ], Group.for(@user).map(&:key)
  end

  test "Ungrouped only appears while some feed has no folder" do
    @loose.destroy

    assert_equal [ "all", folders(:tech).id.to_s ], Group.for(@user).map(&:key)
  end

  test "each group's feeds and items" do
    assert_equal [ @filed, @loose ].sort_by(&:id), Group.find(@user, "all").feeds.sort_by(&:id)
    assert_equal [ @filed ], Group.find(@user, folders(:tech).id).feeds.to_a
    assert_equal [ @loose ], Group.find(@user, "ungrouped").feeds.to_a
    assert_equal @filed.items.unread.count, Group.find(@user, folders(:tech).id).unread_count
  end

  test "find is scoped to the user" do
    assert_raises(ActiveRecord::RecordNotFound) { Group.find(@user, folders(:other_users).id) }
  end

  test "health shows the worst state with a count, and the first feed in that state" do
    assert_equal [ "idle", "OK", nil ], health(Group.find(@user, "all"))

    @loose.update!(last_fetched_at: Time.current, last_item_at: 30.days.ago)
    assert_equal [ "warn", "1 STALE", @loose ], health(Group.find(@user, "all"))

    @filed.update!(last_fetched_at: Time.current, last_fetch_error_at: Time.current, last_fetch_status: "503")
    assert_equal [ "fail", "1 ERR", @filed ], health(Group.find(@user, "all"))
    assert_equal [ "warn", "1 STALE", @loose ], health(Group.find(@user, "ungrouped"))
  end

  test "containing names the All feeds row and the feed's own group" do
    assert_equal [ "all", folders(:tech).id.to_s ], Group.containing(@filed).map(&:key)
    assert_equal [ "all", "ungrouped" ], Group.containing(@loose).map(&:key)
  end

  private

  def health(group)
    summary = group.health
    [ summary.tone, summary.label, summary.feed ]
  end
end

# RDR-01 FeedTree: the left pane's mode is a per-user setting (Groups by
# default). Feeds cache their volume — `~N items / wk` and the newest
# item's time — because every tree row's STALE check needs both.
class AddGroupsModeAndFeedVolume < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tree_mode, :string, default: "groups", null: false
    add_column :feeds, :items_per_week, :float, default: 0.0, null: false
    add_column :feeds, :last_item_at, :datetime

    reversible do |direction|
      direction.up do
        # Same definitions as Feed#refresh_volume!.
        execute <<~SQL
          UPDATE feeds SET
            last_item_at = (SELECT MAX(COALESCE(items.published_at, items.created_at)) FROM items WHERE items.feed_id = feeds.id),
            items_per_week = (SELECT COUNT(*) FROM items WHERE items.feed_id = feeds.id
                                AND COALESCE(items.published_at, items.created_at) >= datetime('now', '-56 days')) / 8.0
        SQL
      end
    end
  end
end

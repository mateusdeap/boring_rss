# The feed view's facts (RDR-01 ModeFeeds): when the current failure
# streak began (last_fetch_error_at is only the latest failure), when the
# next poll or retry is due, the last successful fetch, and the feed's
# WebSub hub if it names one (shown, not subscribed to).
class AddFetchScheduleToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :failing_since, :datetime
    add_column :feeds, :next_fetch_at, :datetime
    add_column :feeds, :last_ok_at, :datetime
    add_column :feeds, :last_ok_status, :string
    add_column :feeds, :last_ok_bytes, :integer
    add_column :feeds, :websub_hub, :string
    add_index :feeds, :next_fetch_at

    reversible do |direction|
      direction.up do
        # Best available: a streak's start is at most its latest failure.
        execute "UPDATE feeds SET failing_since = last_fetch_error_at WHERE last_fetch_error_at IS NOT NULL"
        execute <<~SQL
          UPDATE feeds SET
            last_ok_at = last_fetched_at, last_ok_status = last_fetch_status, last_ok_bytes = last_fetch_bytes
          WHERE last_fetch_error_at IS NULL AND last_fetched_at IS NOT NULL
        SQL
      end
    end
  end
end

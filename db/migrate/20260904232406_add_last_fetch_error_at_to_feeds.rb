class AddLastFetchErrorAtToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :last_fetch_error_at, :datetime
  end
end

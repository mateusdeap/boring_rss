class AddLastFetchBytesToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :last_fetch_bytes, :integer
  end
end

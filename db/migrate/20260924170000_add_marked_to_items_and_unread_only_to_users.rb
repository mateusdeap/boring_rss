class AddMarkedToItemsAndUnreadOnlyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :marked, :boolean, default: false, null: false
    add_column :users, :unread_only, :boolean, default: false, null: false
  end
end

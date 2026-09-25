# RDR-01 ItemTable: a river's sort (TIME or FEED) is remembered per group,
# keyed by Group#key ("all", "ungrouped", a folder id). Missing = TIME.
class AddItemSortsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :item_sorts, :json, default: {}, null: false
  end
end

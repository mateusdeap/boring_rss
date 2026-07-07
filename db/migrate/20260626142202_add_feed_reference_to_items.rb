class AddFeedReferenceToItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :items, :feed, null: false, foreign_key: true
  end
end

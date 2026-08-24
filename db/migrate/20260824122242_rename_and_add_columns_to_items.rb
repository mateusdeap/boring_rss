class RenameAndAddColumnsToItems < ActiveRecord::Migration[8.1]
  def change
    rename_column :items, :pub_date, :published_at
    rename_column :items, :description, :summary
    add_column :items, :guid, :string
    add_index :items, [:feed_id, :guid], unique: true
  end
end

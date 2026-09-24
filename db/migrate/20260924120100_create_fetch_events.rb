class CreateFetchEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :fetch_events do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :status, null: false
      t.integer :bytes
      t.integer :new_items_count, default: 0, null: false
      t.integer :duration_ms
      t.string :detail
      t.datetime :created_at, null: false
    end

    add_index :fetch_events, [ :feed_id, :created_at ]
    add_index :fetch_events, :created_at
  end
end

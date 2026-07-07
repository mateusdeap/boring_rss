class CreateFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :feeds do |t|
      t.string :title
      t.string :link
      t.string :description

      t.timestamps
    end
  end
end

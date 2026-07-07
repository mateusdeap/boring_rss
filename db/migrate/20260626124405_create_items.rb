class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.string :title
      t.string :link
      t.string :description

      t.timestamps
    end
  end
end

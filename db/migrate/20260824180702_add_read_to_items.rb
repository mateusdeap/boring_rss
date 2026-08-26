class AddReadToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :read, :boolean, default: false, null: false
  end
end

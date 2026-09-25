class AddReaderSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :reader_text_size, :integer, null: false, default: 16
    add_column :users, :reader_measure, :integer, null: false, default: 68
    add_column :users, :reader_details_expanded, :boolean, null: false, default: true
  end
end

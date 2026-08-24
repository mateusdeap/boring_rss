class AddPubDateToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :pub_date, :datetime
  end
end

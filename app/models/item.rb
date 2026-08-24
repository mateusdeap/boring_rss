class Item < ApplicationRecord
  belongs_to :feed

  after_create_commit -> { broadcast_prepend_to feed, target: "items", partial: "items/list_item", locals: { item: self } }
end

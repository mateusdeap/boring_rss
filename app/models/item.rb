class Item < ApplicationRecord
  belongs_to :feed

  scope :unread, -> { where(read: false) }
  scope :marked, -> { where(marked: true) }

  after_create_commit :broadcast_creation

  def mark_read!
    return if read?

    update!(read: true)
    broadcast_replace_later_to feed, target: self, partial: "items/list_item", locals: { item: self }
    feed.broadcast_row_later
  end

  private

  def broadcast_creation
    broadcast_prepend_to feed, target: "items", partial: "items/list_item", locals: { item: self }
    feed.broadcast_row
  end
end

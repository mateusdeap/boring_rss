class Feed < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  accepts_nested_attributes_for :items

  validates_presence_of :link

  def unread_count
    items.unread.count
  end
end

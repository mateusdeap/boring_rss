class Feed < ApplicationRecord
  has_many :items
  accepts_nested_attributes_for :items

  validates_presence_of :link
end

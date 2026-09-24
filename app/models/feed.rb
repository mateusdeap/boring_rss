class Feed < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  accepts_nested_attributes_for :items

  validates_presence_of :link

  def unread_count
    items.unread.count
  end

  def record_fetch_success!
    return unless last_fetch_error_at

    update!(last_fetch_error_at: nil)
    broadcast_replace_to :feeds, target: self, partial: "feeds/feed", locals: { feed: self }
  end

  def record_fetch_failure!
    update!(last_fetch_error_at: Time.current)
    broadcast_replace_to :feeds, target: self, partial: "feeds/feed", locals: { feed: self }
  end
end

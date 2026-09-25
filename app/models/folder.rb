# One level of grouping in the feed tree (RDR-01 FeedTree folders). A feed
# belongs to at most one folder; `folder_id: nil` is the top level.
# Folders are created by name wherever a feed is filed (Add feed, Move
# feed) and deleted explicitly — deleting one moves its feeds to the top
# level rather than deleting them. `collapsed` is persisted so the tree
# opens the way it was left.
class Folder < ApplicationRecord
  belongs_to :user
  has_many :feeds, dependent: :nullify

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 64 }, uniqueness: { scope: :user_id }

  scope :alphabetical, -> { order(Arel.sql("name COLLATE NOCASE")) }

  def unread_count
    Item.joins(:feed).where(feeds: { folder_id: id }).unread.count
  end

  # RDR-01: "Folders show the worst health of their children."
  def health
    Feed.health_summary(feeds.sort_by(&:id))
  end

  def last_fetched_at
    feeds.filter_map(&:last_fetched_at).max
  end

  # The folder's tree row, on the owner's own stream (see Feed#broadcast_row).
  def broadcast_row
    broadcast_replace_to user, :feeds, target: self, partial: "folders/folder", locals: { folder: self }
  end

  def broadcast_row_later
    broadcast_replace_later_to user, :feeds, target: self, partial: "folders/folder", locals: { folder: self }
  end
end

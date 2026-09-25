# A reading river in the left pane's Groups mode (RDR-01 FeedTree): All
# feeds, one per folder, or Ungrouped (the feeds with no folder). Nothing
# here is stored — a group is a view over the user's feeds, and its counts
# and health are derived from them.
#
# `key` names it in URLs and DOM ids: "all", "ungrouped", or the folder's id.
class Group
  ALL = "all"
  UNGROUPED = "ungrouped"

  attr_reader :user, :folder

  # The rows of Groups mode, in order: All feeds, each folder, then
  # Ungrouped when any feed has no folder.
  def self.for(user)
    groups = [ new(user, ALL) ]
    groups.concat(user.folders.alphabetical.map { |folder| new(user, folder) })
    groups << new(user, UNGROUPED) if user.feeds.where(folder_id: nil).exists?
    groups
  end

  # Raises ActiveRecord::RecordNotFound for another user's folder or an
  # unknown key, like a scoped find.
  def self.find(user, key)
    case key.to_s
    when ALL, UNGROUPED then new(user, key.to_s)
    else new(user, user.folders.find(key))
    end
  end

  # The groups whose rows show this feed's counts and health.
  def self.containing(feed)
    [ new(feed.user, ALL), new(feed.user, feed.folder || UNGROUPED) ]
  end

  def initialize(user, folder_or_key)
    @user = user
    @folder = folder_or_key if folder_or_key.is_a?(Folder)
    @key = @folder ? @folder.id.to_s : folder_or_key
  end

  def key = @key
  def to_param = key
  def all? = key == ALL
  def ungrouped? = key == UNGROUPED

  def name
    if all? then "All feeds"
    elsif ungrouped? then "Ungrouped"
    else folder.name
    end
  end

  def dom_id
    "group_#{key}"
  end

  def feeds
    if all? then user.feeds
    elsif ungrouped? then user.feeds.where(folder_id: nil)
    else folder.feeds
    end
  end

  # Tree order: folders alphabetically, then the top level; by id within.
  def feeds_in_tree_order
    feeds.includes(:folder).sort_by { |feed| [ feed.folder ? 0 : 1, feed.folder&.name.to_s.downcase, feed.id ] }
  end

  def items
    Item.where(feed_id: feeds.select(:id))
  end

  def unread_count
    items.unread.count
  end

  def health
    Feed.health_summary(feeds_in_tree_order)
  end

  def ==(other)
    other.is_a?(Group) && other.user == user && other.key == key
  end
  alias eql? ==

  def hash = [ user.id, key ].hash

  # The row on the owner's own feeds stream (see Feed#broadcast_row). The
  # later variant's locals go through Active Job, which can't serialize a
  # Group, so the row is rebuilt from its user and folder-or-key.
  def broadcast_row
    Turbo::StreamsChannel.broadcast_replace_to user, :feeds, target: dom_id, partial: "groups/group", locals: row_locals
  end

  def broadcast_row_later
    Turbo::StreamsChannel.broadcast_replace_later_to user, :feeds, target: dom_id, partial: "groups/group", locals: row_locals
  end

  private

  def row_locals
    { user:, group_key: folder || key }
  end
end

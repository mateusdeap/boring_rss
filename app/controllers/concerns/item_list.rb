# The item list shown in the ITEMS pane (feeds/_items.html.erb). Loaded by
# FeedsController#show, and by ItemsController#show on a full-page load
# (an item's own URL), which renders the whole app with that item's feed.
module ItemList
  extend ActiveSupport::Concern

  private

  def load_item_list(feed)
    @feed = feed
    @unread_count = feed.unread_count
    @items = feed.items.order(published_at: :desc)
    @items = @items.unread if Current.user.unread_only?
  end

  # A group's merged river (Groups mode): every item of its feeds, newest
  # first — under one header row per feed, in tree order, when the group
  # is sorted by FEED.
  def load_group_list(group)
    @group = group
    @sort = Current.user.item_sort(group)
    @feeds = group.feeds_in_tree_order
    @unread_count = group.unread_count
    @items = group.items.includes(:feed).order(published_at: :desc)
    @items = @items.unread if Current.user.unread_only?
  end
end

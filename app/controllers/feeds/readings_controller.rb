# "Mark all read" for one feed. The button sits inside the current_feed
# turbo-frame, so redirecting back to the feed re-renders the item list
# (with the unread-only filter applied, if on).
class Feeds::ReadingsController < ApplicationController
  def create
    feed = Current.user.feeds.find(params[:feed_id])
    feed.mark_all_read!
    redirect_to feed_path(feed), status: :see_other
  end
end

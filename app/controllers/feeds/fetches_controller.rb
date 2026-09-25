# FETCH NOW in the feed view: polls this one feed right away instead of
# waiting for its next scheduled poll. The result lands in the view's
# FetchLog and the left pane live, as any poll does.
class Feeds::FetchesController < ApplicationController
  def create
    feed = Current.user.feeds.find(params[:feed_id])
    UpdateFeedsJob.perform_later(feed_id: feed.id)
    redirect_to feed_path(feed), status: :see_other
  end
end

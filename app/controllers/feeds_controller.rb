class FeedsController < ApplicationController
  include FeedTreeStreams
  include ItemList

  def index
  end

  # Renders into the current_feed frame, or — loaded as its own URL (the
  # tree's links advance the address bar) — the whole app on the ITEMS
  # screen.
  def show
    load_item_list(Current.user.feeds.find(params[:id]))
  end

  def new
    @feed = Feed.new
  end

  def create
    feed = InitializeFeed.new(link: feed_params[:link], user: Current.user).call
    feed.folder_name = feed_params[:folder_name] if feed.errors.empty?

    # `save` calls `valid?`, which clears `errors` before re-running
    # validations — that would wipe the specific message InitializeFeed
    # already attached on its RSS::Error rescue path and replace it with a
    # generic `can't be blank`. Skip `save` entirely once that's happened;
    # there's nothing to persist and nothing left to validate.
    if feed.errors.empty? && feed.save
      feed.refresh_volume!
      respond_to do |format|
        format.turbo_stream { render turbo_stream: tree_streams }
        format.html { redirect_to :feeds }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render :new, assigns: { feed: feed }, status: :unprocessable_content
        end
        format.html do
          render :new, assigns: { feed: feed }, status: :unprocessable_content
        end
      end
    end
  end

  # Renames a feed or moves it to another group: the feed view's RENAME…
  # and MOVE TO GROUP… dialogs, and the left pane's context menu. From the
  # feed view (from=feed_view) the answer also re-renders that view, whose
  # header names both.
  def update
    feed = Current.user.feeds.find(params[:id])
    attributes = params.expect(feed: [ :title, :folder_name ])
    feed.title = attributes[:title].to_s.squish if attributes.key?(:title)
    feed.folder_name = attributes[:folder_name] if attributes.key?(:folder_name)

    if feed.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: tree_streams + feed_view_streams(feed) }
        format.html { redirect_to feed }
      end
    else
      render_dialog_error dialog_error_target(attributes), feed
    end
  end

  # UNSUBSCRIBE… in the feed view leaves for the start page, since the
  # view's own URL is gone; the context menu's delete stays put.
  def destroy
    feed = Current.user.feeds.find(params[:id])
    feed.destroy
    return redirect_to(root_path, status: :see_other) if from_feed_view?

    respond_to do |format|
      format.turbo_stream { render turbo_stream: tree_streams }
      format.html { redirect_to :feeds }
    end
  end

  private

  def from_feed_view?
    params[:from] == "feed_view"
  end

  def feed_view_streams(feed)
    return [] unless from_feed_view?

    load_item_list(feed)
    [ turbo_stream.update("current_feed", partial: "feeds/view") ]
  end

  def dialog_error_target(attributes)
    return "move-feed-error" unless from_feed_view?

    attributes.key?(:title) ? "feed-view-rename-error" : "feed-view-move-error"
  end

  def feed_params
    params.expect(feed: [ :link, :folder_name ])
  end
end

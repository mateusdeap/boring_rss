class FeedsController < ApplicationController
  def index
    @feeds = Current.user.feeds
  end

  def show
    @feed = Current.user.feeds.find(params[:id])
  end

  def new
    @feed = Feed.new
  end

  def create
    feed = InitializeFeed.new(link: feed_params[:link], user: Current.user).call

    # `save` calls `valid?`, which clears `errors` before re-running
    # validations — that would wipe the specific message InitializeFeed
    # already attached on its RSS::Error rescue path and replace it with a
    # generic `can't be blank`. Skip `save` entirely once that's happened;
    # there's nothing to persist and nothing left to validate.
    if feed.errors.empty? && feed.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(:feeds, partial: "feeds/feed", locals: { feed: feed })
        end
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

  def destroy
    feed = Current.user.feeds.find(params[:id])
    feed.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(feed) }
      format.html { redirect_to :feeds }
    end
  end

  private

  def feed_params
    params.expect(feed: [ :link ])
  end
end

class FeedsController < ApplicationController
  def index
    @feeds = Feed.all
  end

  def show
    @feed = Feed.find(params[:id])
  end

  def new
    @feed = Feed.new
  end

  def create
    feed = InitializeFeed.new(link: feed_params[:link]).call

    if feed.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(:feeds, partial: "feeds/feed", locals: {feed: feed})
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
    feed = Feed.find(params[:id])
    feed.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(feed) }
      format.html { redirect_to :feeds }
    end
  end

  private

  def feed_params
    params.expect(feed: [:link])
  end
end

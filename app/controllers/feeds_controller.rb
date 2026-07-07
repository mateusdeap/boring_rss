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
      render :new, status: :unprocessable_content
    end
  end

  private

  def feed_params
    params.expect(feed: [:link])
  end
end

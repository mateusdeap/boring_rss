# The Marked view: every item the user has marked (M), across all feeds,
# newest first. Renders into the current_feed frame like FeedsController#show.
class MarkedItemsController < ApplicationController
  def index
    @items = Current.user.items.marked.includes(:feed).order(published_at: :desc)
  end
end

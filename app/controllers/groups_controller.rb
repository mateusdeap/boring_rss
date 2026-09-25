# A group's merged river (RDR-01 FeedTree, Groups mode): All feeds, a
# folder, or Ungrouped. Renders into the current_feed frame like
# FeedsController#show, or — loaded as its own URL — the whole app.
class GroupsController < ApplicationController
  include ItemList

  def show
    load_group_list(Group.find(Current.user, params[:id]))
  end
end

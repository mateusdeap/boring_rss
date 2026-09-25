# "Mark all read" for a river ([⇧R] in a group's toolbar), like
# Feeds::ReadingsController for one feed.
class Groups::ReadingsController < ApplicationController
  def create
    group = Group.find(Current.user, params[:group_id])
    group.mark_all_read!
    redirect_to group_path(group), status: :see_other
  end
end

# A river's sort, TIME or FEED (RDR-01 ItemTable, the [S] control),
# remembered per group. The control sits inside the current_feed frame,
# so redirecting back to the group re-renders the list in place.
class Groups::SortsController < ApplicationController
  def update
    group = Group.find(Current.user, params[:group_id])
    sort = params[:sort]
    Current.user.update!(item_sorts: Current.user.item_sorts.merge(group.key => sort)) if User::ITEM_SORTS.include?(sort)
    redirect_to group_path(group), status: :see_other
  end
end

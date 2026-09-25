# [R] POLL NOW, offered by the reader when nothing is unread: polls the
# signed-in user's feeds now instead of waiting for the recurring job.
class PollsController < ApplicationController
  def create
    UpdateFeedsJob.perform_later(user_id: Current.user.id)
    redirect_to root_path, status: :see_other
  end
end

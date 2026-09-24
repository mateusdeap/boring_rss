class PreferencesController < ApplicationController
  # Theme (status bar select) and the unread-only filter (item table
  # toolbar). The filter button sits inside the current_feed turbo-frame,
  # whose Referer is the page, not the frame — so it passes return_to (the
  # feed) explicitly; url_from only accepts same-host URLs.
  def update
    Current.user.update!(preference_params)
    redirect_to url_from(params[:return_to]) || request.referer || root_path, status: :see_other
  end

  private

  def preference_params
    params.expect(user: [ :theme, :unread_only ])
  end
end

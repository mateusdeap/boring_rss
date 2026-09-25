class PreferencesController < ApplicationController
  # Theme (status bar select), the unread-only filter (item table toolbar),
  # the left pane's mode and the reader's text size, measure and details
  # state. The filter
  # button sits inside the current_feed turbo-frame, whose Referer is the
  # page, not the frame — so it passes return_to (the feed) explicitly;
  # url_from only accepts same-host URLs. The reader's settings are saved
  # in the background as JSON (reader_text/reader_details controllers).
  def update
    saved = Current.user.update(preference_params)

    respond_to do |format|
      format.json { saved ? head(:no_content) : render(json: Current.user.errors, status: :unprocessable_content) }
      format.html do
        redirect_to url_from(params[:return_to]) || request.referer || root_path, status: :see_other
      end
    end
  end

  private

  def preference_params
    params.expect(user: [ :theme, :unread_only, :reader_text_size, :reader_measure, :reader_details_expanded, :tree_mode ])
  end
end

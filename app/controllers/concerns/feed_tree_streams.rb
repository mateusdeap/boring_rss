# Turbo Stream responses shared by everything that changes the feed tree's
# *structure* (add/move/delete a feed, rename/delete a folder). The tree is
# a flat list — folder row, then its feeds — so rather than splice rows
# into the right place, these re-render both modes' lists plus the folder-name
# <datalist> the Add feed and Move feed dialogs suggest from. Count and
# health changes don't come through here: those replace single rows via
# Feed#broadcast_row / Folder#broadcast_row.
module FeedTreeStreams
  extend ActiveSupport::Concern

  private

  def tree_streams
    [
      turbo_stream.update("groups", partial: "groups/tree", locals: { user: Current.user }),
      turbo_stream.update("feeds", partial: "feeds/tree", locals: { user: Current.user }),
      turbo_stream.replace("folder-names", partial: "folders/datalist", locals: { user: Current.user })
    ]
  end

  # A dialog form failed validation: show the reason inside the still-open
  # dialog. 422 keeps add_feed_modal_controller.js from closing it.
  def render_dialog_error(target, record)
    render turbo_stream: turbo_stream.update(target, "ERR #{record.errors.full_messages.to_sentence}"),
           status: :unprocessable_content
  end
end

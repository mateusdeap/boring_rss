class FoldersController < ApplicationController
  include FeedTreeStreams

  # Two callers: the rename dialog (a Turbo form, re-renders the tree) and
  # the tree's collapse toggle (a background fetch from
  # selection_controller.js, which has already updated the DOM itself and
  # only needs the state persisted).
  def update
    folder = Current.user.folders.find(params[:id])

    if folder.update(folder_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: tree_streams }
        format.json { head :no_content }
        format.html { redirect_to :feeds }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_dialog_error "rename-folder-error", folder }
        format.json { render json: { errors: folder.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  # Feeds in the folder move to the top level (Folder has_many :feeds,
  # dependent: :nullify); nothing else is deleted.
  def destroy
    Current.user.folders.find(params[:id]).destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: tree_streams }
      format.html { redirect_to :feeds }
    end
  end

  private

  def folder_params
    params.expect(folder: [ :name, :collapsed ])
  end
end

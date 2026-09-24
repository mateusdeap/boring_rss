# Marks and unmarks an item. Responds with Turbo Streams that re-render the
# item's table row, the reader's MARK button and the tree's MARKED count,
# for both callers: the
# reader's button_to and the M key (selection_controller.js, which renders
# the response itself via Turbo.renderStreamMessage).
class Items::MarksController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_item

  def create
    @item.update!(marked: true)
    render_mark
  end

  def destroy
    @item.update!(marked: false)
    render_mark
  end

  private

  def set_item
    @item = Current.user.items.find(params[:item_id])
  end

  def render_mark
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@item, partial: "items/list_item", locals: { item: @item }),
          turbo_stream.replace(dom_id(@item, :mark), partial: "items/mark_button", locals: { item: @item }),
          turbo_stream.replace("marked_view", partial: "feeds/marked_row", locals: { user: Current.user })
        ]
      end
      format.html { redirect_to @item, status: :see_other }
    end
  end
end

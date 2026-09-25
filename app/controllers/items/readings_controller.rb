# Marks an item read or unread — the reader's [U] toggle (opening an item
# already marks it read, in ItemsController#show). Answers with Turbo
# Streams re-rendering the item's table row and the reader's UNREAD button;
# the feed tree's counts follow through Item#broadcast_read_state.
class Items::ReadingsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_item

  def create
    @item.mark_read!
    render_reading
  end

  def destroy
    @item.mark_unread!
    render_reading
  end

  private

  def set_item
    @item = Current.user.items.find(params[:item_id])
  end

  def render_reading
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@item, partial: "items/list_item", locals: { item: @item }),
          turbo_stream.replace(dom_id(@item, :reading), partial: "items/reading_button", locals: { item: @item })
        ]
      end
      format.html { redirect_to @item, status: :see_other }
    end
  end
end

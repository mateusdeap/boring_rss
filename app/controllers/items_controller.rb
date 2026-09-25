class ItemsController < ApplicationController
  include ItemList

  before_action :set_item, only: %i[show edit update destroy]

  # GET /items or /items.json
  def index
    @items = Current.user.items
  end

  # Opening an item marks it read (reading pane spec: read on open, [U]
  # undoes it). The item is open within a list, which its URL names:
  # /groups/:group_id/items/:id, /feeds/:feed_id/items/:id,
  # /marked/items/:id, or /items/:id for its own feed. Renders into the
  # current_item frame, or — loaded as its own URL (item links advance the
  # address bar) — the whole app with that list and the item open.
  # TODO: still a side effect on GET — see "Known deferred fixes" in CLAUDE.md.
  def show
    set_list
    @item.mark_read!
    return if turbo_frame_request?

    case @list
    when Group then load_group_list(@list)
    when Feed then load_item_list(@list)
    else @items = Current.user.items.marked.includes(:feed).order(published_at: :desc)
    end
  end

  # GET /items/first_unread — the newest unread item across every feed.
  def first_unread
    item = Current.user.items.unread.order(published_at: :desc).first
    redirect_to item ? feed_item_path(item.feed, item) : root_path
  end

  # GET /items/new
  def new
    @item = Item.new
  end

  # GET /items/1/edit
  def edit
  end

  # POST /items or /items.json
  def create
    @item = Item.new(item_params)

    respond_to do |format|
      if @item.save
        format.html { redirect_to @item, notice: "Item was successfully created." }
        format.json { render :show, status: :created, location: @item }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @item.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /items/1 or /items/1.json
  def update
    respond_to do |format|
      if @item.update(item_params)
        format.html { redirect_to @item, notice: "Item was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @item }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @item.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /items/1 or /items/1.json
  def destroy
    @item.destroy!

    respond_to do |format|
      format.html { redirect_to items_path, notice: "Item was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  # The list the item is open in: @list (a Group, a Feed, or :marked) and
  # @list_path, where the reader's back links go. An item outside the list
  # its URL names is not found there.
  def set_list
    if params[:group_id]
      @list = Group.find(Current.user, params[:group_id])
      raise ActiveRecord::RecordNotFound unless @list.items.exists?(@item.id)
      @list_path = group_path(@list)
    elsif request.path.start_with?("/marked/")
      @list = :marked
      @list_path = marked_items_path
    else
      @list = params[:feed_id] ? Current.user.feeds.find(params[:feed_id]) : @item.feed
      raise ActiveRecord::RecordNotFound unless @list == @item.feed
      @list_path = feed_path(@list)
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_item
    @item = Current.user.items.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def item_params
    params.expect(item: [ :title, :link, :summary ])
  end
end

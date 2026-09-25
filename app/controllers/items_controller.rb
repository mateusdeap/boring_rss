class ItemsController < ApplicationController
  include ItemList

  before_action :set_item, only: %i[show edit update destroy]

  # GET /items or /items.json
  def index
    @items = Current.user.items
  end

  # Opening an item marks it read (reading pane spec: read on open, [U]
  # undoes it). Renders into the current_item frame, or — loaded as its own
  # URL (item links advance the address bar) — the whole app with the
  # item's feed listed and the item open.
  # TODO: still a side effect on GET — see "Known deferred fixes" in CLAUDE.md.
  def show
    @item.mark_read!
    load_item_list(@item.feed) unless turbo_frame_request?
  end

  # GET /items/first_unread — the newest unread item across every feed.
  def first_unread
    item = Current.user.items.unread.order(published_at: :desc).first
    redirect_to item || root_path
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

  # Use callbacks to share common setup or constraints between actions.
  def set_item
    @item = Current.user.items.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def item_params
    params.expect(item: [ :title, :link, :summary ])
  end
end

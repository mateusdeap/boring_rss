class Item < ApplicationRecord
  # Reading speed behind the reader's "~6 min" estimates.
  WORDS_PER_MINUTE = 200

  belongs_to :feed

  # full: <content:encoded>/Atom <content>; excerpt: only <description>/Atom
  # <summary>; empty: none of them. Set at ingest (InitializeItems).
  enum :content_kind, { full: "full", excerpt: "excerpt", empty: "empty" }, prefix: :content, default: "empty"

  scope :unread, -> { where(read: false) }
  scope :marked, -> { where(marked: true) }

  before_save :count_content, if: :summary_changed?
  after_create_commit :broadcast_creation

  def mark_read!
    return if read?

    update!(read: true)
    broadcast_read_state
  end

  def mark_unread!
    return unless read?

    update!(read: false)
    broadcast_read_state
  end

  def reading_minutes
    return 0 if word_count.zero?

    (word_count.to_f / WORDS_PER_MINUTE).round.clamp(1..)
  end

  private

  def count_content
    fragment = Nokogiri::HTML5.fragment(summary.to_s)
    self.word_count = fragment.text.split.size
    self.image_count = fragment.css("img").count { |img| !ReaderScrubber.pixel?(img) }
    self.link_count = fragment.css("a[href]").size
  end

  # Called from controller actions, hence the _later variants. The row goes
  # to the owner's own stream, which the app shell subscribes to once, so
  # it reaches whichever list shows it — a feed, a group's river, Marked.
  def broadcast_read_state
    broadcast_replace_later_to feed.user, :feeds, target: self, partial: "items/list_item", locals: { item: self }
    feed.broadcast_row_later
  end

  # A new item lands in every list on the owner's screen that includes its
  # feed: on top of a newest-first list (a feed, or a river sorted by TIME,
  # whose #items names its feeds in data-feed-ids), or under its feed's
  # header in a river sorted by FEED.
  def broadcast_creation
    broadcast_prepend_to feed.user, :feeds, targets: "#items[data-sort='time'][data-feed-ids~='#{feed_id}']",
                         partial: "items/list_item", locals: { item: self }
    broadcast_after_to feed.user, :feeds, target: "feedhead_#{feed_id}", partial: "items/list_item", locals: { item: self }
    feed.broadcast_row
  end
end

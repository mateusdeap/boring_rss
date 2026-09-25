class Feed < ApplicationRecord
  # Polled every POLL_INTERVAL while healthy. After a failure, retried
  # after each of RETRY_DELAYS in turn, then every RETRY_CAP; the first
  # RETRY_ATTEMPTS count as "attempt n/8", and polling never stops.
  POLL_INTERVAL = 30.minutes
  RETRY_DELAYS = [ 30.minutes, 1.hour, 2.hours, 4.hours ].freeze
  RETRY_CAP = 6.hours
  RETRY_ATTEMPTS = 8

  # Feeds whose next poll or retry is due (never-polled ones included).
  scope :due, ->(now = Time.current) { where(next_fetch_at: nil).or(where(next_fetch_at: ..now)) }

  # Volume is measured over the last VOLUME_WINDOW of items.
  VOLUME_WINDOW = 8.weeks
  # STALE (RDR-01 `warn`: "no new items past its expected interval"): the
  # newest item is older than three of the feed's usual gaps between items
  # (a week over its items per week), and never sooner than STALE_AFTER.
  STALE_GAPS = 3
  STALE_AFTER = 14.days

  # The worst health across some feeds, for a group or folder row:
  # `1 ERR` over `1 STALE` over `OK`. `feed` is the first one failing (or
  # stale) in the order given, which the row's health link opens.
  HealthSummary = Data.define(:tone, :label, :feed, :failing, :stale)

  def self.health_summary(feeds)
    failing = feeds.select(&:fetch_failed?)
    stale = feeds.select { |feed| !feed.fetch_failed? && feed.stale? }

    if failing.any?
      HealthSummary.new("fail", "#{failing.size} ERR", failing.first, failing, stale)
    elsif stale.any?
      HealthSummary.new("warn", "#{stale.size} STALE", stale.first, failing, stale)
    else
      HealthSummary.new(feeds.any?(&:last_fetched_at?) ? "ok" : "idle", "OK", nil, failing, stale)
    end
  end

  belongs_to :user
  belongs_to :folder, optional: true
  has_many :items, dependent: :destroy
  has_many :fetch_events, dependent: :delete_all
  accepts_nested_attributes_for :items

  validates_presence_of :link
  # Renamed in the feed view; polls never overwrite it.
  validates :title, presence: true, length: { maximum: 200 }, if: :title_changed?
  validate :folder_belongs_to_owner

  def unread_count
    items.unread.count
  end

  # "Mark all read" for this feed. One UPDATE, no per-item callbacks — the
  # caller re-renders the item list; the tree row (and its folder's) is
  # re-broadcast here. Returns how many items changed.
  def mark_all_read!
    count = items.unread.update_all(read: true, updated_at: Time.current)
    broadcast_row_later if count.positive?
    count
  end

  def fetch_failed?
    last_fetch_error_at?
  end

  def stale?(now: Time.current)
    return false unless last_item_at

    gap = items_per_week.positive? ? 1.week.to_f / items_per_week : 0
    last_item_at < now - [ gap * STALE_GAPS, STALE_AFTER.to_f ].max
  end

  # fail / stale / ok, or unknown before the first poll. The tree rows'
  # data-health, read by the StatusBar.
  def health
    if fetch_failed? then "fail"
    elsif !last_fetched_at? then "unknown"
    elsif stale? then "stale"
    else "ok"
    end
  end

  # Recomputes the cached volume after items were added: items per week
  # over the last VOLUME_WINDOW, and the newest item's time. An item with no
  # date counts from when it was stored.
  def refresh_volume!
    dated = items.pluck(Arel.sql("COALESCE(published_at, items.created_at)")).compact
    recent = dated.count { |time| time >= VOLUME_WINDOW.ago }
    update_columns(items_per_week: recent / VOLUME_WINDOW.in_weeks, last_item_at: dated.max)
  end

  def folder_name
    folder&.name
  end

  # Files the feed by folder *name*: blank means the top level, an unknown
  # name creates the folder (saved along with the feed). Always scoped to
  # the feed's owner.
  def folder_name=(name)
    self.folder = name.to_s.squish.presence && user.folders.find_or_initialize_by(name:)
  end

  # Records one poll (UpdateFeedsJob): appends a FetchEvent for the log and
  # updates the feed's own last-fetch state, which the feed tree, status
  # bar and feed view read, and schedules the next poll. A failure extends
  # the streak (`failing_since`, `fetch_failures_count`, the latest in
  # `last_fetch_error_at`) and schedules a retry, named in the log's
  # detail; a success ends the streak and becomes the LAST OK fetch.
  # Validators (ETag, Last-Modified) are only replaced when the server sent
  # new ones — a 304 often omits them. `websub_hub` is only updated from a
  # parsed body (`hub: false` leaves it).
  def record_fetch!(status:, detail:, bytes: nil, new_items_count: 0, duration_ms: nil, etag: nil, last_modified: nil, hub: false)
    now = Time.current
    failed = FetchEvent.failure?(status)
    attributes = { last_fetched_at: now, last_fetch_status: status, last_fetch_detail: detail, last_fetch_bytes: bytes }

    if failed
      failures = fetch_failures_count + 1
      attributes.merge!(last_fetch_error_at: now, failing_since: failing_since || now, fetch_failures_count: failures,
                        next_fetch_at: now + self.class.retry_delay(failures))
      detail = [ detail.presence, retry_note(attributes[:next_fetch_at], failures) ].compact.join(" · ")
    else
      attributes.merge!(last_fetch_error_at: nil, failing_since: nil, fetch_failures_count: 0, next_fetch_at: now + POLL_INTERVAL,
                        last_ok_at: now, last_ok_status: status, last_ok_bytes: bytes)
      attributes[:etag] = etag if etag.present?
      attributes[:last_modified] = last_modified if last_modified.present?
      attributes[:websub_hub] = hub unless hub == false
    end

    transaction do
      fetch_events.create!(status:, detail:, bytes:, new_items_count:, duration_ms:, created_at: now)
      update!(attributes)
    end

    broadcast_row
  end

  def self.retry_delay(failures)
    RETRY_DELAYS[failures - 1] || RETRY_CAP
  end

  # `retry 08:28Z (attempt 3/8)`, or, past the counted attempts,
  # `retry 14:28Z (every 6 h)`.
  def retry_note(at = next_fetch_at, failures = fetch_failures_count)
    return unless at

    attempt = failures <= RETRY_ATTEMPTS ? "attempt #{failures}/#{RETRY_ATTEMPTS}" : "every #{RETRY_CAP.in_hours.to_i} h"
    "retry #{at.utc.strftime("%H:%MZ")} (#{attempt})"
  end

  # The feed tree row, on the owner's own stream — never a stream shared
  # across accounts, which would push one user's feed titles to everyone
  # subscribed.
  # The folder row aggregates its feeds' unread counts and health, so it's
  # re-rendered alongside.
  # Groups mode's rows (All feeds, and the feed's folder or Ungrouped)
  # aggregate the same counts and health, so they follow too.
  # A river sorted by FEED heads this feed's items with a row of its own
  # (items/_feedhead), which follows along.
  def broadcast_row
    broadcast_replace_to user, :feeds, target: self, partial: "feeds/feed", locals: { feed: self }
    broadcast_replace_to user, :feeds, target: "feedhead_#{id}", partial: "items/feedhead", locals: { feed: self }
    folder&.broadcast_row
    Group.containing(self).each(&:broadcast_row)
  end

  def broadcast_row_later
    broadcast_replace_later_to user, :feeds, target: self, partial: "feeds/feed", locals: { feed: self }
    broadcast_replace_later_to user, :feeds, target: "feedhead_#{id}", partial: "items/feedhead", locals: { feed: self }
    folder&.broadcast_row_later
    Group.containing(self).each(&:broadcast_row_later)
  end

  private

  def folder_belongs_to_owner
    errors.add(:folder, "must belong to the feed's owner") if folder && folder.user_id != user_id
  end
end

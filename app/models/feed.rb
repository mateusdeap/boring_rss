class Feed < ApplicationRecord
  belongs_to :user
  belongs_to :folder, optional: true
  has_many :items, dependent: :destroy
  has_many :fetch_events, dependent: :delete_all
  accepts_nested_attributes_for :items

  validates_presence_of :link
  validate :folder_belongs_to_owner

  def unread_count
    items.unread.count
  end

  def fetch_failed?
    last_fetch_error_at?
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
  # updates the feed's own last-fetch state, which the feed tree and status
  # bar read. `last_fetch_error_at`/`fetch_failures_count` track the current
  # failure streak and reset on the next success. Validators (ETag,
  # Last-Modified) are only replaced when the server sent new ones — a 304
  # often omits them.
  def record_fetch!(status:, detail:, bytes: nil, new_items_count: 0, duration_ms: nil, etag: nil, last_modified: nil)
    now = Time.current
    failed = FetchEvent.failure?(status)

    transaction do
      fetch_events.create!(status:, detail:, bytes:, new_items_count:, duration_ms:, created_at: now)

      attributes = { last_fetched_at: now, last_fetch_status: status, last_fetch_detail: detail }
      if failed
        attributes.merge!(last_fetch_error_at: now, fetch_failures_count: fetch_failures_count + 1)
      else
        attributes.merge!(last_fetch_error_at: nil, fetch_failures_count: 0)
        attributes[:etag] = etag if etag.present?
        attributes[:last_modified] = last_modified if last_modified.present?
      end
      update!(attributes)
    end

    broadcast_row
  end

  # The feed tree row, on the owner's own stream — never a stream shared
  # across accounts, which would push one user's feed titles to everyone
  # subscribed.
  # The folder row aggregates its feeds' unread counts and health, so it's
  # re-rendered alongside.
  def broadcast_row
    broadcast_replace_to user, :feeds, target: self, partial: "feeds/feed", locals: { feed: self }
    folder&.broadcast_row
  end

  def broadcast_row_later
    broadcast_replace_later_to user, :feeds, target: self, partial: "feeds/feed", locals: { feed: self }
    folder&.broadcast_row_later
  end

  private

  def folder_belongs_to_owner
    errors.add(:folder, "must belong to the feed's owner") if folder && folder.user_id != user_id
  end
end

# One poll of one feed by UpdateFeedsJob — the rows behind RDR-01's
# FetchLog. `status` is the HTTP status as a string ("200", "304", "503")
# or, when there was no usable HTTP response, a state word (see
# UpdateFeedsJob::FAILURE_WORDS). Pruned after RETENTION by the job.
class FetchEvent < ApplicationRecord
  RETENTION = 1.day

  belongs_to :feed

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  after_create_commit :broadcast_to_log

  # RDR-01 StatusCode tones: 2xx/304 ok, other 3xx warn, everything else
  # (4xx, 5xx, and every state word) fail.
  def self.tone(status)
    return "fail" unless status.to_s.match?(/\A\d{3}\z/)

    code = status.to_i
    if code.between?(200, 299) || code == 304 then "ok"
    elsif code.between?(300, 399) then "warn"
    else "fail"
    end
  end

  def self.failure?(status)
    tone(status) == "fail"
  end

  def self.prune(before: RETENTION.ago)
    where(created_at: ...before).delete_all
  end

  def tone
    self.class.tone(status)
  end

  private

  # Runs from UpdateFeedsJob (outside any request), so synchronous is fine —
  # same convention as Item#broadcast_creation.
  def broadcast_to_log
    broadcast_prepend_to feed, target: "fetch_log", partial: "fetch_events/fetch_event", locals: { fetch_event: self }
  end
end

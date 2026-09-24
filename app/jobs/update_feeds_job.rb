require "net/http"
require "openssl"
require "resolv"

class UpdateFeedsJob < ApplicationJob
  queue_as :default

  # When a poll gets no usable HTTP response, the FetchEvent/feed status is
  # one of these words instead of a status code (RDR-01 StatusCode: the text
  # carries the meaning). Checked in order; anything unlisted is "ERR".
  FAILURE_WORDS = {
    "TIMEOUT" => [ Net::OpenTimeout, Net::ReadTimeout, Timeout::Error ],
    "DNS" => [ SocketError, Resolv::ResolvError ],
    "CONN" => [ Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH ],
    "TLS" => [ OpenSSL::SSL::SSLError ],
    "PARSE" => [ RSS::Error ],
    "REDIR" => [ FeedFetcher::TooManyRedirects ],
    "SIZE" => [ FeedFetcher::TooLarge ],
    "URL" => [ FeedFetcher::UnsupportedURL ]
  }.freeze

  def perform
    Feed.includes(:user).find_each { |feed| poll(feed) }
    FetchEvent.prune
  end

  private

  # A per-feed `rescue StandardError` keeps one broken/unreachable feed from
  # aborting the loop for every feed after it (see CLAUDE.md) — and now also
  # records *what* went wrong instead of just that something did.
  def poll(feed)
    started = monotonic_ms
    response = FeedFetcher.fetch(feed.feed_url, etag: feed.etag, last_modified: feed.last_modified)
    duration_ms = monotonic_ms - started

    if response.not_modified?
      feed.record_fetch!(status: "304", detail: join("Not modified", validators(response), via(response)),
                         bytes: response.bytes, duration_ms:, etag: response.etag, last_modified: response.last_modified)
    elsif response.success?
      record_success(feed, response, duration_ms)
    else
      feed.record_fetch!(status: response.status.to_s, detail: join(response.reason.presence || "HTTP error", via(response)),
                         bytes: response.bytes, duration_ms:)
    end
  rescue StandardError => e
    Rails.logger.warn("Fetch failed for feed #{feed.id} (#{feed.feed_url}): #{e.class}: #{e.message}")
    feed.record_fetch!(status: failure_word(e), detail: "#{e.class}: #{e.message}".truncate(250),
                       duration_ms: started && monotonic_ms - started)
  end

  # Dedup is identity-based (guid, falling back to link), not date-based —
  # Atom's `published` is optional.
  def record_success(feed, response, duration_ms)
    parsed_feed = ParsedFeed.parse_xml(response.body)
    entries = parsed_feed.entries
    existing_identities = feed.items.pluck(:guid, :link).map { |guid, link| guid.presence || link }.to_set
    new_entries = entries.reject { |entry| existing_identities.include?(entry.guid.presence || entry.link) }
    feed.items << InitializeItems.new(new_entries).call

    feed.record_fetch!(
      status: response.status.to_s,
      detail: join("#{parsed_feed.format} · #{entries.size} entries · #{new_entries.size} new", validators(response), via(response)),
      bytes: response.bytes, new_items_count: new_entries.size, duration_ms:,
      etag: response.etag, last_modified: response.last_modified
    )
  end

  def failure_word(error)
    FAILURE_WORDS.find { |_word, classes| classes.any? { |klass| error.is_a?(klass) } }&.first || "ERR"
  end

  def validators(response)
    "ETag #{response.etag}" if response.etag.present?
  end

  def via(response)
    return if response.redirects.empty?

    status, from = response.redirects.first
    "via #{status} from #{from}"
  end

  def join(*parts)
    parts.compact_blank.join(" · ")
  end

  def monotonic_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  end
end

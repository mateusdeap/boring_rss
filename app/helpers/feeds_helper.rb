module FeedsHelper
  # RDR-01 StatusCode: a square marker plus the code or word, coloured by
  # FetchEvent.tone. Never the marker alone.
  def status_code_tag(status, **options)
    tag.span(status, class: "r-code r-code-#{FetchEvent.tone(status)}", **options)
  end

  # `ERR 503 Service Unavailable — failing since 2026-09-24 08:14Z (3 consecutive)`
  def fetch_failure_summary(feed)
    since = feed.fetch_failures_count > 1 ? " (#{pluralize(feed.fetch_failures_count, "consecutive failure")})" : ""
    "ERR #{feed.last_fetch_status} #{feed.last_fetch_detail} — last attempt #{rdr_time(feed.last_fetch_error_at)}#{since}"
  end
end

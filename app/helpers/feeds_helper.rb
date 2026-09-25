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

  # A feed's health as one StatusCode: the failing code or word, STALE, OK,
  # or an idle dash before the first poll.
  def feed_health_tag(feed, **options)
    case feed.health
    when "fail" then status_code_tag(feed.last_fetch_status, title: fetch_failure_summary(feed), **options)
    when "stale" then tag.span("STALE", class: "r-code r-code-warn", **options)
    when "ok" then tag.span("OK", class: "r-code r-code-ok", **options)
    else tag.span("—", class: "r-code r-code-idle", title: "Not fetched since it was added", **options)
    end
  end

  # `~12 items / wk`, `<1 item / wk`, `0 items / wk` (RDR-01: units on every
  # number).
  def items_per_week_label(feed)
    rate = feed.items_per_week
    if rate.zero? then "0 items / wk"
    elsif rate < 1 then "<1 item / wk"
    else "~#{rdr_number(rate.round)} items / wk"
    end
  end
end

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

  # -- The feed view's facts (feeds/_view) --------------------------------
  # Verbose on purpose (RDR-01: an error says what happened, with the code).

  # `503 Service Unavailable · failing since 2026-09-21 06:10Z · retry
  # 08:28Z (attempt 3/8)`, or `200 OK · fetched … · next …`.
  def feed_status_fact(feed)
    return safe_join([ tag.span("—", class: "rdr-tone rdr-tone-idle"), "not fetched yet · first fetch #{next_fetch_label(feed)}" ], " ") unless feed.last_fetched_at?

    parts = [ fetch_status_tag(feed) ]
    if feed.fetch_failed?
      parts << tag.span(feed.last_fetch_detail, class: "r-2") unless feed.last_fetch_status.to_s.match?(/\A\d+\z/)
      parts << "failing since #{rdr_time(feed.failing_since || feed.last_fetch_error_at)}"
      parts << feed.retry_note if feed.next_fetch_at
    else
      parts << "fetched #{rdr_time(feed.last_fetched_at)} (#{rdr_age(feed.last_fetched_at)} ago)"
      parts << "next #{next_fetch_label(feed)}"
      parts << tag.span("STALE — no new items in #{rdr_age(feed.last_item_at)}", class: "rdr-tone rdr-tone-warn") if feed.stale?
    end
    safe_join(parts, " · ")
  end

  # `2026-09-21 05:40Z · 200 · 41.2 kB · ETag "7be2…"`
  def feed_last_ok_fact(feed)
    return tag.span("never", class: "r-dim") unless feed.last_ok_at?

    parts = [ rdr_time(feed.last_ok_at), feed.last_ok_status ]
    parts << rdr_bytes(feed.last_ok_bytes) if feed.last_ok_bytes
    parts << short_etag(feed.etag) if feed.etag.present?
    parts.compact.join(" · ")
  end

  # `poll every 30 min · no WebSub hub · sends ETag and Last-Modified`
  def feed_schedule_fact(feed)
    validators = [ ("ETag" if feed.etag.present?), ("Last-Modified" if feed.last_modified.present?) ].compact
    [
      "poll every #{Feed::POLL_INTERVAL.in_minutes.to_i} min",
      feed.websub_hub ? "WebSub hub #{bare_url(feed.websub_hub)} (not subscribed)" : "no WebSub hub",
      validators.any? ? "sends #{validators.to_sentence(two_words_connector: " and ")}" : "sends no validators"
    ].join(" · ")
  end

  # `~2 items / wk · last item 3 d ago · 214 items kept`
  def feed_volume_fact(feed)
    [
      items_per_week_label(feed),
      (feed.last_item_at ? "last item #{rdr_age(feed.last_item_at)} ago" : "no items yet"),
      "#{pluralize(rdr_number(feed.items.size), "item")} kept"
    ].join(" · ")
  end

  # `08:44Z (in 12 min)`, or `due now`.
  def next_fetch_label(feed)
    at = feed.next_fetch_at
    return "due now" if at.nil? || at <= Time.current

    "#{at.utc.strftime("%H:%MZ")} (in #{rdr_age(Time.current, now: at)})"
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

module ApplicationHelper
  # RDR-01 names its two themes Paper (light) and Carbon (dark). Only the
  # labels changed — the stored enum values stay light/dark.
  THEME_LABELS = { "system" => "System", "light" => "Paper", "dark" => "Carbon" }.freeze

  # RDR-01 content rules: thin space as the thousands separator.
  THIN_SPACE = " ".freeze

  # "system" means follow the OS via prefers-color-scheme (no attribute
  # needed); only an explicit light/dark preference needs to be stamped
  # onto <body> to override that media query. Deliberately <body>, not
  # <html> — see the comment in app/assets/tailwind/application.css.
  def theme_attribute
    return {} unless authenticated? && !Current.user.system?

    { "data-theme": Current.user.theme }
  end

  def theme_options
    User.themes.keys.map { |theme| [ THEME_LABELS.fetch(theme), theme ] }
  end

  # Absolute time, ISO 8601 UTC to the minute: `2026-09-24 08:14Z`.
  def rdr_time(time)
    time.utc.strftime("%Y-%m-%d %H:%MZ")
  end

  # Relative age for lists: `4 min`, `3 h`, `12 d`.
  def rdr_age(time, now: Time.current)
    seconds = (now - time).to_i.clamp(0..)

    if seconds < 1.hour
      "#{seconds / 1.minute} min"
    elsif seconds < 2.days
      "#{seconds / 1.hour} h"
    else
      "#{rdr_number(seconds / 1.day)} d"
    end
  end

  # A relative age whose hover reveals the absolute time.
  def rdr_age_tag(time)
    tag.time(rdr_age(time), datetime: time.utc.iso8601, title: rdr_time(time))
  end

  def rdr_number(number)
    number_with_delimiter(number, delimiter: THIN_SPACE)
  end

  # Sizes in kB/MB, base 1000.
  def rdr_bytes(bytes)
    if bytes < 1_000
      "#{bytes} B"
    elsif bytes < 1_000_000
      "#{format("%.1f", bytes / 1_000.0)} kB"
    else
      "#{format("%.1f", bytes / 1_000_000.0)} MB"
    end
  end
end

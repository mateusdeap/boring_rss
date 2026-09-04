module ApplicationHelper
  # "system" means follow the OS via prefers-color-scheme (no attribute
  # needed); only an explicit light/dark preference needs to be stamped
  # onto <body> to override that media query. Deliberately <body>, not
  # <html> — see the comment in app/assets/tailwind/application.css.
  def theme_attribute
    return {} unless authenticated? && !Current.user.system?

    { "data-theme": Current.user.theme }
  end
end

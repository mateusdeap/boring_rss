module ItemsHelper
  SAFE_LINK_SCHEMES = %w[http https].freeze

  # Rails' `sanitize` default allow-list drops table markup entirely, which
  # would silently eat any table a feed embeds. This list is what the
  # reader's `.r-body` rules (app/assets/tailwind/application.css) actually
  # style — deliberately not "the default list plus tables," since that
  # would also admit tags (dl/kbd/samp/mark/...) the reader has no
  # treatment for.
  SUMMARY_ALLOWED_TAGS = %w[
    p h2 h3 h4 blockquote pre ul ol li hr
    table thead tbody tfoot tr td th
    a strong b em i code br img span
  ].freeze

  def safe_item_link(link)
    uri = URI.parse(link)
    uri.to_s if uri.is_a?(URI::HTTP) && SAFE_LINK_SCHEMES.include?(uri.scheme)
  rescue URI::InvalidURIError
    nil
  end

  def sanitized_summary(item)
    sanitize(item.summary, tags: SUMMARY_ALLOWED_TAGS)
  end
end

module ItemsHelper
  SAFE_LINK_SCHEMES = %w[http https].freeze

  def safe_item_link(link)
    uri = URI.parse(link)
    uri.to_s if uri.is_a?(URI::HTTP) && SAFE_LINK_SCHEMES.include?(uri.scheme)
  rescue URI::InvalidURIError
    nil
  end
end

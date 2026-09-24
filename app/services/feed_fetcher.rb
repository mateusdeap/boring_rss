require "net/http"

# Fetches a feed URL over HTTP(S) and reports exactly what happened —
# status, reason phrase, size, validators, redirects — so UpdateFeedsJob can
# record it (RDR-01: "expose state and inner workings"). This replaces
# letting RSS::Parser.parse fetch the URL itself via open-uri, which hides
# all of that and raises on anything but a 2xx.
#
# Sends a conditional GET when the feed has a stored ETag/Last-Modified, so
# an unchanged feed answers 304 with no body. Follows up to MAX_REDIRECTS
# redirects; a 304 is *not* followed even though Net::HTTPNotModified is a
# Net::HTTPRedirection subclass. Non-2xx final responses are returned, not
# raised — deciding what counts as failure is the caller's job. Transport
# problems (DNS, refused, timeout, TLS) raise Net/Socket/OpenSSL errors as
# usual; the errors below cover what this class itself rejects.
class FeedFetcher
  class Error < StandardError; end
  class UnsupportedURL < Error; end
  class TooManyRedirects < Error; end
  class TooLarge < Error; end

  MAX_REDIRECTS = 5
  MAX_BYTES = 10_000_000
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  USER_AGENT = "BoringRSS/1.0 (+https://github.com/mateusdeap/boring_rss)".freeze
  ACCEPT = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.8".freeze

  Response = Data.define(:status, :reason, :body, :etag, :last_modified, :url, :redirects) do
    def bytes = body.bytesize
    def success? = status.between?(200, 299)
    def not_modified? = status == 304
  end

  def self.fetch(url, etag: nil, last_modified: nil)
    new(url, etag:, last_modified:).fetch
  end

  def initialize(url, etag: nil, last_modified: nil)
    @url = url
    @etag = etag
    @last_modified = last_modified
  end

  # Returns a Response. `redirects` lists each hop as [status, from_url].
  def fetch
    uri = parse_uri(@url)
    redirects = []

    loop do
      response, body = request(uri)

      if response.is_a?(Net::HTTPRedirection) && !response.is_a?(Net::HTTPNotModified)
        raise TooManyRedirects, "More than #{MAX_REDIRECTS} redirects from #{@url}" if redirects.size >= MAX_REDIRECTS

        location = response["location"].presence or raise UnsupportedURL, "#{response.code} redirect without a Location header"
        redirects << [ response.code.to_i, uri.to_s ]
        uri = parse_uri(uri.merge(location).to_s)
        next
      end

      return Response.new(
        status: response.code.to_i,
        reason: response.message.to_s.strip,
        body: encode(body, response.type_params["charset"]),
        etag: response["etag"],
        last_modified: response["last-modified"],
        url: uri.to_s,
        redirects:
      )
    end
  end

  private

  def parse_uri(url)
    uri = URI.parse(url.to_s.strip)
    raise UnsupportedURL, "Not an http(s) URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri
  rescue URI::InvalidURIError => e
    raise UnsupportedURL, e.message
  end

  # Returns [response, body]; the body is read inside the block so it can be
  # capped while streaming.
  def request(uri)
    body = +""
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(build_request(uri)) { |streaming| body = read_capped(streaming) }
    end
    [ response, body ]
  end

  def build_request(uri)
    Net::HTTP::Get.new(uri).tap do |request|
      request["User-Agent"] = USER_AGENT
      request["Accept"] = ACCEPT
      request["If-None-Match"] = @etag if @etag.present?
      request["If-Modified-Since"] = @last_modified if @last_modified.present?
    end
  end

  # Streams the body so an oversized response is abandoned at MAX_BYTES
  # instead of being buffered whole. Net::HTTP still transparently
  # decompresses gzip/deflate, so the limit (and Response#bytes) is on the
  # decoded body.
  def read_capped(response)
    body = +""
    response.read_body do |chunk|
      body << chunk
      raise TooLarge, "Response exceeded #{MAX_BYTES / 1_000_000} MB" if body.bytesize > MAX_BYTES
    end
    body
  end

  # open-uri (the old fetch path) tagged the body with the Content-Type
  # charset; keep doing that so RSS::Parser sees the same strings it did.
  def encode(body, charset)
    return body.b if charset.blank?

    body.force_encoding(charset)
  rescue ArgumentError
    body.b
  end
end

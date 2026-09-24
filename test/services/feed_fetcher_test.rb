require "test_helper"
require "socket"

class FeedFetcherTest < ActiveSupport::TestCase
  setup do
    @requests = []
    @routes = {}
    @server = TCPServer.new("127.0.0.1", 0)
    @base = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new { serve }
  end

  teardown do
    @thread.kill
    @server.close
  end

  test "returns status, reason, body, size and validators" do
    route "/rss", "200 OK", { "ETag" => %("v1"), "Last-Modified" => "Wed, 23 Sep 2026 10:00:00 GMT", "Content-Type" => "application/rss+xml; charset=utf-8" }, "<rss/>"

    response = FeedFetcher.fetch("#{@base}/rss")

    assert response.success?
    assert_equal 200, response.status
    assert_equal "OK", response.reason
    assert_equal "<rss/>", response.body
    assert_equal Encoding::UTF_8, response.body.encoding
    assert_equal 6, response.bytes
    assert_equal %("v1"), response.etag
    assert_equal "Wed, 23 Sep 2026 10:00:00 GMT", response.last_modified
  end

  test "sends conditional headers and returns a 304 without following it" do
    route "/rss", "304 Not Modified", {}, ""

    response = FeedFetcher.fetch("#{@base}/rss", etag: %("v1"), last_modified: "Wed, 23 Sep 2026 10:00:00 GMT")

    assert response.not_modified?
    assert_match(/If-None-Match: "v1"/i, @requests.last)
    assert_match(/If-Modified-Since: Wed, 23 Sep 2026 10:00:00 GMT/i, @requests.last)
  end

  test "follows redirects and reports the hops" do
    route "/old", "301 Moved Permanently", { "Location" => "/new" }, ""
    route "/new", "200 OK", {}, "<rss/>"

    response = FeedFetcher.fetch("#{@base}/old")

    assert_equal 200, response.status
    assert_equal "#{@base}/new", response.url
    assert_equal [ [ 301, "#{@base}/old" ] ], response.redirects
  end

  test "gives up after too many redirects" do
    route "/loop", "302 Found", { "Location" => "/loop" }, ""

    assert_raises(FeedFetcher::TooManyRedirects) { FeedFetcher.fetch("#{@base}/loop") }
  end

  test "returns error statuses instead of raising" do
    route "/rss", "503 Service Unavailable", {}, "down"

    response = FeedFetcher.fetch("#{@base}/rss")

    assert_equal 503, response.status
    assert_equal "Service Unavailable", response.reason
    assert_not response.success?
  end

  test "rejects non-http URLs, including local paths" do
    assert_raises(FeedFetcher::UnsupportedURL) { FeedFetcher.fetch("/etc/hosts") }
    assert_raises(FeedFetcher::UnsupportedURL) { FeedFetcher.fetch("file:///etc/hosts") }
  end

  private

  def route(path, status_line, headers, body)
    @routes[path] = [ status_line, headers, body ]
  end

  # A minimal one-request-per-connection HTTP/1.1 server; enough for
  # Net::HTTP without adding a test dependency.
  def serve
    loop do
      client = @server.accept
      request = +""
      while (line = client.gets) && line != "\r\n"
        request << line
      end
      @requests << request

      path = request[/\AGET (\S+)/, 1]
      status_line, headers, body = @routes.fetch(path, [ "404 Not Found", {}, "" ])
      head = [ "HTTP/1.1 #{status_line}", "Content-Length: #{body.bytesize}", "Connection: close" ]
      head += headers.map { |name, value| "#{name}: #{value}" }
      client.write(head.join("\r\n") + "\r\n\r\n" + body)
      client.close
    end
  rescue IOError
    # server closed in teardown
  end
end

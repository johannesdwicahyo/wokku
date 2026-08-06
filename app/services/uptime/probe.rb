require "net/http"

module Uptime
  # One HTTP probe of an app's public URL (Track A Phase 5). Up = the app
  # answered ANYTHING < 500 — a 404 is an alive app. SSL handshake
  # failures retry once over plain http (fresh domains before their cert
  # lands); everything else maps to a typed failure_kind that
  # ReasonClassifier can pass through to the owner.
  class Probe
    TIMEOUT = 5
    MAX_REDIRECTS = 3

    Result = Struct.new(:up, :failure_kind, keyword_init: true) do
      def up? = up
    end

    def self.call(url)
      new.call(url)
    end

    def call(url, redirects_left: MAX_REDIRECTS, ssl_retry_left: true)
      uri = URI.parse(url)
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT, read_timeout: TIMEOUT
      ) { |http| http.get(uri.request_uri.presence || "/") }

      if response.is_a?(Net::HTTPRedirection) && redirects_left.positive? && response["location"].present?
        return call(URI.join(url, response["location"]).to_s,
          redirects_left: redirects_left - 1, ssl_retry_left: ssl_retry_left)
      end
      return Result.new(up: true) if response.code.to_i < 500

      Result.new(up: false, failure_kind: :http_5xx)
    rescue Net::OpenTimeout, Net::ReadTimeout
      Result.new(up: false, failure_kind: :timeout)
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      Result.new(up: false, failure_kind: :connection_refused)
    rescue SocketError
      Result.new(up: false, failure_kind: :dns_error)
    # ponytail: falls back on ANY ssl error, so an EXPIRED cert with a
    # live http vhost reads "up" — scope the fallback to never-verified
    # domains if cert-breakage alerts ever matter.
    rescue OpenSSL::SSL::SSLError
      if ssl_retry_left && url.start_with?("https://")
        call(url.sub("https://", "http://"), redirects_left: redirects_left, ssl_retry_left: false)
      else
        Result.new(up: false, failure_kind: :ssl_error)
      end
    end
  end
end

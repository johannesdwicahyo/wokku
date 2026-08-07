require "net/http"
require "ssrf_filter"

module Uptime
  # One HTTP probe of an app's public URL (Track A Phase 5). Up = the app
  # answered ANYTHING < 500 — a 404 is an alive app. SSL handshake
  # failures retry once over plain http (fresh domains before their cert
  # lands); everything else maps to a typed failure_kind that
  # ReasonClassifier can pass through to the owner.
  #
  # SSRF guard: app domains are attacker-controllable (any team member can
  # add one), so the probe MUST NOT let the control plane reach loopback,
  # private, or link-local addresses. SsrfFilter resolves the host, rejects
  # non-public IPs, pins the socket to the validated IP (anti-rebinding),
  # and revalidates every redirect hop.
  class Probe
    TIMEOUT = 5
    MAX_REDIRECTS = 3

    Result = Struct.new(:up, :failure_kind, keyword_init: true) do
      def up? = up
    end

    def self.call(url)
      new.call(url)
    end

    def call(url, ssl_retry_left: true)
      response = SsrfFilter.get(url,
        max_redirects: MAX_REDIRECTS,
        http_options: { open_timeout: TIMEOUT, read_timeout: TIMEOUT })

      return Result.new(up: true) if response.code.to_i < 500

      Result.new(up: false, failure_kind: :http_5xx)
    rescue SsrfFilter::Error
      # Destination resolved to a non-public IP (loopback/private/link-local)
      # or exceeded the redirect budget — never probe internal addresses on a
      # team member's behalf. Reads as unreachable to the owner.
      Result.new(up: false, failure_kind: :blocked)
    rescue Net::OpenTimeout, Net::ReadTimeout
      Result.new(up: false, failure_kind: :timeout)
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      Result.new(up: false, failure_kind: :connection_refused)
    rescue SocketError
      Result.new(up: false, failure_kind: :dns_error)
    # ponytail: falls back on ANY ssl error, so an EXPIRED cert with a
    # live http vhost reads "up" — scope the fallback to never-verified
    # domains if cert-breakage alerts ever matter. The http retry is STILL
    # SsrfFilter-guarded, so the downgrade can't reach internal addresses.
    rescue OpenSSL::SSL::SSLError
      if ssl_retry_left && url.start_with?("https://")
        call(url.sub("https://", "http://"), ssl_retry_left: false)
      else
        Result.new(up: false, failure_kind: :ssl_error)
      end
    end
  end
end

require "net/http"
require "json"

module Cloudflare
  class Dns
    BASE_URL = "https://api.cloudflare.com/client/v4"

    # Per-domain zone-id env-var mapping. Add a new entry when we onboard
    # another zone; the service supports an arbitrary number.
    ZONE_ID_ENV = {
      "wokku.cloud" => "CLOUDFLARE_ZONE_ID",
      "wokku.app"   => "CLOUDFLARE_ZONE_ID_WOKKU_APP"
    }.freeze

    # The "headline" domain — the one we show on /pricing, in the
    # dashboard "your app URL" copy, and emit as the default `default_url`
    # for new apps. Flipped via the WOKKU_APP_ENABLED env flag once DNS
    # propagation is confirmed.
    CANONICAL_DOMAIN_WHEN_ENABLED = "wokku.app".freeze
    LEGACY_DOMAIN                 = "wokku.cloud".freeze

    class ApiError < StandardError; end

    # ---------------------------------------------------------------------
    # Class-level helpers for callers that need to iterate over every
    # active zone (create_app_record, delete_app_record, set_proxied!)
    # without knowing which zones are configured.
    # ---------------------------------------------------------------------

    def self.wokku_app_enabled?
      ENV["WOKKU_APP_ENABLED"].to_s.downcase.in?(%w[1 true yes on])
    end

    # Which zones we should write to. wokku.cloud always; wokku.app only
    # when the flag is on. Existing wokku.cloud records keep being
    # maintained forever so external links never break.
    def self.enabled_domains
      domains = [ LEGACY_DOMAIN ]
      domains << CANONICAL_DOMAIN_WHEN_ENABLED if wokku_app_enabled?
      domains
    end

    # The domain we MARKET as primary — what user-facing URLs default to.
    def self.canonical_domain
      wokku_app_enabled? ? CANONICAL_DOMAIN_WHEN_ENABLED : LEGACY_DOMAIN
    end

    # Both the legacy wokku.cloud and the canonical wokku.app are valid
    # Wokku-owned hostnames — used by views to decide "is this a wokku
    # subdomain or a user's custom domain?"
    def self.owned_domains
      [ LEGACY_DOMAIN, CANONICAL_DOMAIN_WHEN_ENABLED ].uniq
    end

    # Yields a fresh per-zone instance for every enabled domain. Callers
    # use this to write the same record to all active zones in one pass.
    def self.for_each_enabled
      enabled_domains.each do |domain|
        yield new(domain: domain)
      end
    end

    # ---------------------------------------------------------------------
    # Instance API — one Dns instance writes to ONE zone.
    # ---------------------------------------------------------------------

    attr_reader :domain

    def initialize(domain: LEGACY_DOMAIN)
      @domain  = domain
      @token   = ENV.fetch("CLOUDFLARE_API_TOKEN")
      env_var  = ZONE_ID_ENV.fetch(domain) do
        raise ArgumentError, "Cloudflare::Dns: no zone mapping for domain #{domain.inspect}"
      end
      @zone_id = ENV.fetch(env_var) do
        raise ApiError, "Cloudflare::Dns: #{env_var} not set; cannot write to #{domain} zone"
      end
    end

    # Create an A record for an app subdomain pointing to its server.
    # Example: create_app_record("my-app", "103.xx.xx.xx") on a wokku.app
    # instance writes my-app.wokku.app → A → 103.xx.xx.xx.
    def create_app_record(app_name, server_ip)
      hostname = "#{app_name}.#{domain}"

      existing = find_record(hostname, "A")
      if existing
        if existing["content"] != server_ip
          update_record(existing["id"], hostname, server_ip)
          Rails.logger.info("Cloudflare::Dns[#{domain}]: Updated #{hostname} → #{server_ip}")
        else
          Rails.logger.info("Cloudflare::Dns[#{domain}]: #{hostname} already points to #{server_ip}")
        end
      else
        body = {
          type: "A",
          name: hostname,
          content: server_ip,
          ttl: 1,
          proxied: false # DNS-only by default; CDN toggle flips this later
        }
        post("/zones/#{@zone_id}/dns_records", body)
        Rails.logger.info("Cloudflare::Dns[#{domain}]: Created #{hostname} → #{server_ip}")
      end

      hostname
    end

    # Toggle the Cloudflare proxy ("orange cloud") for an app subdomain.
    def set_proxied!(app_name, proxied:)
      hostname = "#{app_name}.#{domain}"
      record = find_record(hostname, "A")
      raise ApiError, "DNS record for #{hostname} not found" unless record

      return record if record["proxied"] == proxied

      body = {
        type: "A",
        name: hostname,
        content: record["content"],
        ttl: 1,
        proxied: proxied
      }
      put("/zones/#{@zone_id}/dns_records/#{record['id']}", body)
      Rails.logger.info("Cloudflare::Dns[#{domain}]: #{hostname} proxied=#{proxied}")
      body
    end

    def delete_app_record(app_name)
      hostname = "#{app_name}.#{domain}"
      record = find_record(hostname, "A")
      if record
        delete("/zones/#{@zone_id}/dns_records/#{record['id']}")
        Rails.logger.info("Cloudflare::Dns[#{domain}]: Deleted #{hostname}")
      else
        Rails.logger.info("Cloudflare::Dns[#{domain}]: #{hostname} not found, nothing to delete")
      end
    end

    def list_app_records
      response = get("/zones/#{@zone_id}/dns_records", type: "A", per_page: 100)
      response["result"].select { |r| r["name"].end_with?(".#{domain}") && r["name"] != domain }
    end

    def find_record(hostname, type = "A")
      response = get("/zones/#{@zone_id}/dns_records", type: type, name: hostname)
      response["result"]&.first
    end

    def verify!
      response = get("/zones/#{@zone_id}")
      zone = response["result"]
      {
        name: zone["name"],
        status: zone["status"],
        nameservers: zone["name_servers"]
      }
    end

    private

    def update_record(record_id, hostname, server_ip)
      body = {
        type: "A",
        name: hostname,
        content: server_ip,
        ttl: 1,
        proxied: false
      }
      put("/zones/#{@zone_id}/dns_records/#{record_id}", body)
    end

    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri)
      execute(uri, request)
    end

    def post(path, body)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Post.new(uri)
      request.body = body.to_json
      request.content_type = "application/json"
      execute(uri, request)
    end

    def put(path, body)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Put.new(uri)
      request.body = body.to_json
      request.content_type = "application/json"
      execute(uri, request)
    end

    def delete(path)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Delete.new(uri)
      execute(uri, request)
    end

    def execute(uri, request)
      request["Authorization"] = "Bearer #{@token}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15

      response = http.request(request)
      parsed = JSON.parse(response.body)

      unless parsed["success"]
        errors = parsed["errors"]&.map { |e| e["message"] }&.join(", ") || "Unknown error"
        raise ApiError, "Cloudflare API error: #{errors}"
      end

      parsed
    end
  end
end

require "net/http"
require "json"

module Cloudflare
  class Dns
    BASE_URL = "https://api.cloudflare.com/client/v4"
    DOMAIN = "wokku.cloud"

    class ApiError < StandardError; end

    def initialize
      @token = ENV.fetch("CLOUDFLARE_API_TOKEN")
      @zone_id = ENV.fetch("CLOUDFLARE_ZONE_ID")
    end

    # Create an A record for an app subdomain pointing to its server
    # Example: create_app_record("my-app", "103.xx.xx.xx")
    # Creates: my-app.wokku.cloud → A → 103.xx.xx.xx
    def create_app_record(app_name, server_ip)
      hostname = "#{app_name}.#{DOMAIN}"

      # Check if record already exists
      existing = find_record(hostname, "A")
      if existing
        # Update if IP changed
        if existing["content"] != server_ip
          update_record(existing["id"], hostname, server_ip)
          Rails.logger.info("Cloudflare::Dns: Updated #{hostname} → #{server_ip}")
        else
          Rails.logger.info("Cloudflare::Dns: #{hostname} already points to #{server_ip}")
        end
      else
        body = {
          type: "A",
          name: hostname,
          content: server_ip,
          ttl: 1, # Auto TTL
          proxied: false # DNS-only, Dokku handles SSL
        }
        post("/zones/#{@zone_id}/dns_records", body)
        Rails.logger.info("Cloudflare::Dns: Created #{hostname} → #{server_ip}")
      end

      hostname
    end

    # Delete the A record for an app subdomain
    def delete_app_record(app_name)
      hostname = "#{app_name}.#{DOMAIN}"
      record = find_record(hostname, "A")
      if record
        delete("/zones/#{@zone_id}/dns_records/#{record['id']}")
        Rails.logger.info("Cloudflare::Dns: Deleted #{hostname}")
      else
        Rails.logger.info("Cloudflare::Dns: #{hostname} not found, nothing to delete")
      end
    end

    # List all app DNS records
    def list_app_records
      response = get("/zones/#{@zone_id}/dns_records", type: "A", per_page: 100)
      response["result"].select { |r| r["name"].end_with?(".#{DOMAIN}") && r["name"] != DOMAIN }
    end

    # Find a specific DNS record by hostname and type
    def find_record(hostname, type = "A")
      response = get("/zones/#{@zone_id}/dns_records", type: type, name: hostname)
      response["result"]&.first
    end

    # Verify the zone is accessible (health check)
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

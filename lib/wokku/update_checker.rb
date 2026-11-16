require "net/http"
require "json"

module Wokku
  # Self-host update reminder: the newest release is the version label on the
  # public ghcr.io image's :latest tag. Anonymous registry reads only — no
  # phone-home to wokku.cloud, nothing about the install is sent.
  module UpdateChecker
    REGISTRY = "https://ghcr.io".freeze
    REPO = "johannesdwicahyo/wokku".freeze
    ACCEPT = "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, " \
             "application/vnd.docker.distribution.manifest.v2+json".freeze
    VERSION_FORMAT = /\A(\d{4}\.\d{2}\.\d{2})-[0-9a-f]{7}\z/

    module_function

    # => "2026.11.20-abc1234", or nil if the registry can't be read.
    def latest_version
      token = get_json("#{REGISTRY}/token?scope=repository:#{REPO}:pull")["token"]
      manifest = get_json("#{REGISTRY}/v2/#{REPO}/manifests/latest", token)
      if manifest["manifests"] # multi-arch index → the amd64 image
        digest = manifest["manifests"].find { |m| m.dig("platform", "architecture") == "amd64" }&.dig("digest")
        manifest = get_json("#{REGISTRY}/v2/#{REPO}/manifests/#{digest}", token)
      end
      config = get_json("#{REGISTRY}/v2/#{REPO}/blobs/#{manifest.dig('config', 'digest')}", token)
      version = config.dig("config", "Labels", "org.opencontainers.image.version").to_s
      version.match?(VERSION_FORMAT) ? version : nil
    rescue StandardError => e
      Rails.logger.info("update check: #{e.class}: #{e.message}")
      nil
    end

    # Releases are "YYYY.MM.DD-<sha7>". A different release dated the same day
    # or later is newer; a dev build or unknown version never is.
    def newer?(latest, current)
      l = latest.to_s.match(VERSION_FORMAT)
      c = current.to_s.match(VERSION_FORMAT)
      return false unless l && c && latest != current
      l[1] >= c[1]
    end

    def get_json(url, token = nil, redirects: 3)
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = ACCEPT
      req["Authorization"] = "Bearer #{token}" if token
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
      # Blobs redirect to a CDN; the token is only for ghcr itself.
      return get_json(res["location"], nil, redirects: redirects - 1) if res.is_a?(Net::HTTPRedirection) && redirects.positive?
      raise "#{url} -> #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    end
  end
end

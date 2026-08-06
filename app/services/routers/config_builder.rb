# The single source of truth for a host's routing state (Track B phase B1).
# Canonical: fixed key insertion order + sorted apps/domains, so
# JSON.generate is deterministic and #version is a stable content hash.
# Computed on demand, no stored version — nothing to invalidate.
# ponytail: builds the full config on every heartbeat (~21 apps on jkt-01);
# cache per-server if hosts x apps ever makes this measurable.
module Routers
  class ConfigBuilder
    def initialize(server)
      @server = server
    end

    def as_json
      cert = WildcardCertificate.current
      {
        "listen_mode" => @server.wokkud_router_enabled? ? "live" : "shadow",
        "wildcard_cert" => cert && {
          "fullchain_pem" => cert.fullchain_pem,
          "key_pem" => cert.key_pem,
          "sans" => cert.sans
        },
        "apps" => apps_json
      }
    end

    def version
      Digest::SHA256.hexdigest(JSON.generate(as_json))
    end

    private

    def apps_json
      control_plane_entries + app_entries
    end

    # Self-host: the dashboard itself rides the same Caddy on 80/443 —
    # a synthetic app entry at the canonical apex dialing the local puma
    # (WOKKU_CONTROL_PLANE_UPSTREAM, e.g. 127.0.0.1:3000). The managed
    # cloud never sets the env (its control plane sits behind kamal-proxy
    # on a separate box), so its config bytes — and version hashes — are
    # untouched.
    def control_plane_entries
      upstream = ENV["WOKKU_CONTROL_PLANE_UPSTREAM"]
      return [] if upstream.blank?

      [ {
        "name" => "wokku-control-plane",
        "container_port" => 3000,
        "domains" => [ { "hostname" => Wokku.config.canonical_domain, "tls" => "on_demand" } ],
        "upstreams" => [ { "dial" => upstream } ]
      } ]
    end

    def app_entries
      @server.app_records.includes(:domains).order(:name).filter_map do |app|
        domains = app.domains.sort_by(&:hostname)
        next if domains.empty?
        entry = {
          "name" => app.name,
          "container_port" => app.container_port,
          "domains" => domains.map { |d| { "hostname" => d.hostname, "tls" => tls_mode(d) } },
          "upstreams" => upstreams_for(app)
        }
        # W7: real maintenance flag — wokkud renders the app's vhosts as a
        # Caddy static 503 instead of reverse_proxy. Emitted only when true
        # (appended last) so every other app's JSON — and therefore the
        # config version hash — is byte-identical to before the flag existed.
        entry["maintenance"] = true if app.maintenance_mode?
        entry
      end
    end

    # Flagged apps dial their stable swarm-published port directly, no
    # docker-IP resolution needed (Track B phase B5a). A flagged app with no
    # swarm_port yet (converge hasn't allocated one) falls back to the local
    # entry — the safe default, since converge allocates the port before the
    # flag is meant to change routing.
    def upstreams_for(app)
      if app.wokkud_lifecycle? && app.swarm_port.present?
        [ { "dial" => "127.0.0.1:#{app.swarm_port}" } ]
      else
        [ { "local" => true } ]
      end
    end

    # wildcard  — covered by the platform cert pushed in the payload
    # on_demand — custom domain, DNS-verified: Caddy issues via HTTP-01 on
    #             first hit, gated by the tls_allowed ask endpoint
    # none      — custom domain not yet verified: no issuance possible
    def tls_mode(domain)
      return "wildcard" if domain.managed_subdomain?
      domain.dns_verified? ? "on_demand" : "none"
    end
  end
end

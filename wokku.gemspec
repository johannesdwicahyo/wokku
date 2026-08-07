require_relative "lib/wokku/version"

Gem::Specification.new do |spec|
  spec.name        = "wokku"
  spec.version     = Wokku::VERSION
  spec.authors     = [ "Wokku" ]
  spec.summary     = "Wokku core engine (open-source PaaS)."
  spec.license     = "AGPL-3.0-or-later"
  spec.files       = Dir["{app,config,db,docs,lib,vendor}/**/*"]
  spec.required_ruby_version = ">= 3.4.0"

  spec.add_dependency "rails", ">= 8.1.2"
  # Outbound HTTP to user-controlled destinations (uptime probes, webhook
  # notifications) is SSRF-guarded: resolves + validates public IPs, pins
  # the connection (anti-rebinding), revalidates redirects.
  spec.add_dependency "ssrf_filter", "~> 1.5"
end

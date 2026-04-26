class Rack::Attack
  # Use Redis for distributed rate limiting across Puma processes.
  # Falls back to MemoryStore in test/development if Redis isn't configured.
  Rack::Attack.cache.store = if ENV["REDIS_URL"].present?
    ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"], namespace: "rack_attack")
  else
    ActiveSupport::Cache::MemoryStore.new
  end

  # Web sign-in throttle (Devise /users/sign_in). Kept defensively even though
  # the primary path is OAuth — any POST to this endpoint is a password
  # attempt and should be treated as a credential-stuffing vector.
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  # API login (CLI/MCP). Stricter than the generic /api/ throttle: this
  # endpoint accepts email+password, so it's the #1 credential-stuffing target.
  throttle("api_login/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/auth/login" && req.post?
  end

  throttle("api_login/email", limit: 5, period: 1.minute) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      req.params["email"]&.to_s&.downcase&.strip.presence
    end
  end

  # Fail2Ban: ban an IP for 1 hour after 20 failed API login attempts in 10 min.
  # Triggered by the controller calling Rack::Attack::Fail2Ban.filter on failure.
  blocklist("fail2ban/api_login") do |req|
    Rack::Attack::Fail2Ban.filter(
      "api_login:#{req.ip}",
      maxretry: 20,
      findtime: 10.minutes,
      bantime: 1.hour
    ) do
      false # filter called manually from AuthController#login on failed auth
    end
  end

  # Generic API throttle — catch-all for non-login endpoints.
  throttle("api/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/") && req.path != "/api/v1/auth/login"
  end

  # Webhook endpoints.
  throttle("webhooks/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/webhooks/")
  end

  # Custom 429 response
  self.throttled_responder = ->(req) {
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ { error: "Rate limit exceeded. Retry later." }.to_json ]
    ]
  }

  # Blocklist response (fail2ban bans)
  self.blocklisted_responder = ->(req) {
    [
      403,
      { "Content-Type" => "application/json" },
      [ { error: "Too many failed login attempts. Try again in 1 hour." }.to_json ]
    ]
  }
end

# Log throttled and banned requests to Sentry for monitoring.
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn "[rack-attack] throttled #{req.env['rack.attack.matched']} ip=#{req.ip} path=#{req.path}"
end

ActiveSupport::Notifications.subscribe("blocklist.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn "[rack-attack] blocked #{req.env['rack.attack.matched']} ip=#{req.ip} path=#{req.path}"
  Sentry.capture_message("rack-attack blocked #{req.env['rack.attack.matched']}", level: :warning, extra: { ip: req.ip, path: req.path }) if defined?(Sentry)
end

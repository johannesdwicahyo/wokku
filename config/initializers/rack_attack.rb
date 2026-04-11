class Rack::Attack
  # Use Redis for distributed rate limiting across Puma processes.
  # Falls back to MemoryStore in test/development if Redis isn't configured.
  Rack::Attack.cache.store = if ENV["REDIS_URL"].present?
    ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"], namespace: "rack_attack")
  else
    ActiveSupport::Cache::MemoryStore.new
  end

  # Throttle login attempts
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  # Throttle API requests
  throttle("api/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # Throttle password reset requests
  throttle("password_reset/ip", limit: 3, period: 1.minute) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end

  # Throttle webhook endpoints
  throttle("webhooks/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/webhooks/")
  end

  # Throttle registration
  throttle("registrations/ip", limit: 3, period: 1.minute) do |req|
    req.ip if req.path == "/users" && req.post?
  end

  # Custom 429 response
  self.throttled_responder = ->(req) {
    retry_after = (req.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ { error: "Rate limit exceeded. Retry later." }.to_json ]
    ]
  }
end

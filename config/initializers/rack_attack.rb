# Rate limiting for the wokku control plane. Ships in the engine so a
# self-host install gets brute-force / flood protection out of the box (the
# rack-attack gem's railtie inserts the middleware; this defines the rules).
# The managed cloud appends its own marketing-endpoint throttles on top.
class Rack::Attack
  # Redis for distributed limiting across Puma processes; MemoryStore when
  # REDIS_URL isn't set (single-box self-host, dev, test).
  Rack::Attack.cache.store = if ENV["REDIS_URL"].present?
    ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"], namespace: "rack_attack")
  else
    ActiveSupport::Cache::MemoryStore.new
  end

  # Devise + the API routes accept an optional (.:format) suffix, so an
  # exact-path throttle can be evaded with e.g. /users/sign_in.json. Compare
  # against the path with any trailing .<format> stripped.
  def self.wokku_path(req)
    req.path.sub(/\.[a-zA-Z0-9]+\z/, "")
  end

  # Web sign-in (Devise /users/sign_in) — any POST is a password attempt.
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if wokku_path(req) == "/users/sign_in" && req.post?
  end

  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if wokku_path(req) == "/users/sign_in" && req.post?
      email = req.params["user"].is_a?(Hash) ? req.params["user"]["email"] : nil
      email.downcase.strip if email.is_a?(String)
    end
  end

  # API login (CLI/MCP) — accepts email+password, the #1 stuffing target.
  throttle("api_login/ip", limit: 5, period: 1.minute) do |req|
    req.ip if wokku_path(req) == "/api/v1/auth/login" && req.post?
  end

  throttle("api_login/email", limit: 5, period: 1.minute) do |req|
    if wokku_path(req) == "/api/v1/auth/login" && req.post?
      # Strings only: an array email would get a fresh key per request.
      req.params["email"].downcase.strip.presence if req.params["email"].is_a?(String)
    end
  end

  # Native Sign in with Apple — same per-IP budget as password login.
  throttle("api_apple/ip", limit: 5, period: 1.minute) do |req|
    req.ip if wokku_path(req) == "/api/v1/auth/apple" && req.post?
  end

  throttle("api_mobile_token/ip", limit: 5, period: 1.minute) do |req|
    req.ip if wokku_path(req) == "/api/v1/auth/mobile/token" && req.post?
  end

  # Web side of the iOS handoff: each confirm mints a code.
  throttle("mobile_auth_confirm/ip", limit: 10, period: 1.minute) do |req|
    req.ip if wokku_path(req) == "/mobile/auth/confirm" && req.post?
  end

  # 2FA step of web sign-in. Lockable caps guesses per account; these stop
  # parallel bursts racing past it.
  throttle("two_factor/ip", limit: 10, period: 1.minute) do |req|
    req.ip if wokku_path(req) == "/users/two_factor" && req.post?
  end

  throttle("two_factor/user", limit: 5, period: 1.minute) do |req|
    req.session["two_factor_user_id"]&.to_s if wokku_path(req) == "/users/two_factor" && req.post?
  end

  # Email sign-in code (Users::SignInCodesController). Per-email keys go
  # through SignInCode.normalize so case/whitespace variants share a bucket.
  # A resend counts as a request, keyed on the session's pending email.
  def self.sign_in_code_request?(req)
    req.post? && %w[/users/sign_in/code /users/sign_in/code/resend].include?(wokku_path(req))
  end

  def self.sign_in_code_verify?(req)
    req.post? && wokku_path(req) == "/users/sign_in/code/verify"
  end

  def self.sign_in_code_email(email)
    SignInCode.normalize(email).presence if email.is_a?(String)
  end

  throttle("sign_in_code/request/ip", limit: 10, period: 10.minutes) do |req|
    req.ip if sign_in_code_request?(req)
  end

  # Form body only (req.POST), the same source the controller reads.
  def self.sign_in_code_request_email(req)
    return unless sign_in_code_request?(req)
    sign_in_code_email(wokku_path(req).end_with?("/resend") ? req.session["sign_in_code_email"] : req.POST["email"])
  end

  throttle("sign_in_code/request/email", limit: 3, period: 10.minutes) do |req|
    sign_in_code_request_email(req)
  end

  # Email + IP: one IP can't grind one address all day, but a flood can't
  # lock the victim out for 24 h either (the per-email 3/10 min, Issue's
  # cap and the 30-min human-check bound handle victim-wide floods).
  throttle("sign_in_code/request/email/day", limit: 10, period: 1.day) do |req|
    email = sign_in_code_request_email(req)
    "#{email}|#{req.ip}" if email
  end

  throttle("sign_in_code/verify/ip", limit: 20, period: 10.minutes) do |req|
    req.ip if sign_in_code_verify?(req)
  end

  throttle("sign_in_code/verify/email", limit: 10, period: 10.minutes) do |req|
    sign_in_code_email(req.session["sign_in_code_email"]) if sign_in_code_verify?(req)
  end

  # Defense in depth on top of the per-code attempt cap and daily lock pause.
  throttle("sign_in_code/verify/email/day", limit: 30, period: 1.day) do |req|
    sign_in_code_email(req.session["sign_in_code_email"]) if sign_in_code_verify?(req)
  end

  # Fail2Ban: ban an IP for 1h after 20 failed API logins in 10m. The filter
  # is invoked manually from AuthController#login on failed auth.
  blocklist("fail2ban/api_login") do |req|
    Rack::Attack::Fail2Ban.filter(
      "api_login:#{req.ip}",
      maxretry: 20,
      findtime: 10.minutes,
      bantime: 1.hour
    ) do
      false
    end
  end

  # Device flow (RFC 8628) code minting — each call creates a DB row.
  throttle("device_code_mint/ip", limit: 10, period: 1.hour) do |req|
    req.ip if wokku_path(req) == "/api/v1/auth/device/code" && req.post?
  end

  # Device flow polling — RFC interval 5s; 30/min leaves headroom.
  throttle("device_token_poll/ip", limit: 30, period: 1.minute) do |req|
    req.ip if wokku_path(req) == "/api/v1/auth/device/token" && req.post?
  end

  # Generic API catch-all for non-login endpoints.
  throttle("api/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/") && !%w[/api/v1/auth/login /api/v1/auth/apple /api/v1/auth/mobile/token].include?(wokku_path(req))
  end

  # GitHub App install callback: stops brute-forcing installation ids into
  # the 15-minute adoption window (Github::CallbacksController).
  throttle("github_callback/ip", limit: 20, period: 10.minutes) do |req|
    req.ip if wokku_path(req) == "/github/callback"
  end

  throttle("github_callback/user", limit: 10, period: 10.minutes) do |req|
    req.session["warden.user.user.key"]&.dig(0, 0)&.to_s if wokku_path(req) == "/github/callback"
  end

  # Webhook endpoints.
  throttle("webhooks/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/webhooks/")
  end

  # Web vitals ingest — per-token; 600/min is far above real page traffic.
  throttle("vitals_ingest/token", limit: 600, period: 1.minute) do |req|
    req.params["t"] if wokku_path(req) == "/vitals/ingest" && req.post? && req.params["t"].present?
  end

  self.throttled_responder = ->(req) {
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ { error: "Rate limit exceeded. Retry later." }.to_json ]
    ]
  }

  self.blocklisted_responder = ->(req) {
    [
      403,
      { "Content-Type" => "application/json" },
      [ { error: "Too many failed login attempts. Try again in 1 hour." }.to_json ]
    ]
  }
end

ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn "[rack-attack] throttled #{req.env['rack.attack.matched']} ip=#{req.ip} path=#{req.path}"
end

ActiveSupport::Notifications.subscribe("blocklist.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn "[rack-attack] blocked #{req.env['rack.attack.matched']} ip=#{req.ip} path=#{req.path}"
  Sentry.capture_message("rack-attack blocked #{req.env['rack.attack.matched']}", level: :warning, extra: { ip: req.ip, path: req.path }) if defined?(Sentry)
end

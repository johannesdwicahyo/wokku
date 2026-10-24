module Apple
  # Apple's token endpoints: code → refresh token (stored so it can be
  # revoked), and revoke on account deletion (App Store requirement).
  # Never raises to callers — sign-in and deletion must not depend on Apple.
  class Client
    AUDIENCE   = "https://appleid.apple.com"
    TOKEN_URI  = URI("https://appleid.apple.com/auth/token")
    REVOKE_URI = URI("https://appleid.apple.com/auth/revoke")

    def self.client_secret(client_id)
      now = Time.now.to_i
      JWT.encode({ iss: Config.team_id, iat: now, exp: now + 300, aud: AUDIENCE, sub: client_id },
                 OpenSSL::PKey::EC.new(Config.private_key), "ES256", { kid: Config.key_id })
    end

    def self.exchange_code(code, client_id:)
      res = post(TOKEN_URI, client_id: client_id, client_secret: client_secret(client_id),
                            code: code, grant_type: "authorization_code")
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body)["refresh_token"].presence : nil
    rescue => e
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    end

    def self.revoke(token, client_id:)
      res = post(REVOKE_URI, client_id: client_id, client_secret: client_secret(client_id),
                             token: token, token_type_hint: "refresh_token")
      res.is_a?(Net::HTTPSuccess)
    rescue => e
      Sentry.capture_exception(e) if defined?(Sentry)
      false
    end

    def self.post(uri, form)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
        http.post(uri.path, URI.encode_www_form(form), "Content-Type" => "application/x-www-form-urlencoded")
      end
    end
    private_class_method :post
  end
end

module Apple
  # Verifies an Apple identity token (RS256 JWT) from the iOS app.
  class IdentityToken
    class Invalid < StandardError; end
    class Unavailable < StandardError; end

    ISSUER    = "https://appleid.apple.com"
    JWKS_URI  = URI("https://appleid.apple.com/auth/keys")
    CACHE_KEY = "apple/jwks"

    def self.verify!(token, nonce:)
      claims, _header = JWT.decode(token, nil, true,
                                   algorithms: [ "RS256" ], jwks: method(:jwks),
                                   iss: ISSUER, verify_iss: true,
                                   aud: Config.audiences, verify_aud: true)
      unless ActiveSupport::SecurityUtils.secure_compare(claims["nonce"].to_s, Digest::SHA256.hexdigest(nonce.to_s))
        raise Invalid, "nonce mismatch"
      end
      claims
    rescue JWT::DecodeError => e
      raise Invalid, e.class.name
    end

    # jwt calls this again with kid_not_found: true when Apple rotated keys;
    # drop the cache once so the new set is fetched.
    def self.jwks(options = {})
      Rails.cache.delete(CACHE_KEY) if options[:kid_not_found]
      JWT::JWK::Set.new(Rails.cache.fetch(CACHE_KEY, expires_in: 24.hours) { fetch_jwks })
    end

    def self.fetch_jwks
      res = Net::HTTP.start(JWKS_URI.host, JWKS_URI.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.get(JWKS_URI.path)
      end
      raise Unavailable, "Apple JWKS HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError => e
      raise Unavailable, e.class.name
    end
  end
end

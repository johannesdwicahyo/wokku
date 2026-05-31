require "net/http"
require "json"

module Bitbucket
  class TokenRefresher
    class TokenRevoked < StandardError; end
    class RefreshFailed < StandardError; end

    OAUTH_URL = "https://bitbucket.org/site/oauth2/access_token"

    def initialize(user)
      @user = user
    end

    def refresh!
      uri = URI(OAUTH_URL)
      req = Net::HTTP::Post.new(uri)
      req.basic_auth(ENV.fetch("BITBUCKET_OAUTH_CLIENT_ID"), ENV.fetch("BITBUCKET_OAUTH_CLIENT_SECRET"))
      req.set_form_data(
        "grant_type" => "refresh_token",
        "refresh_token" => @user.bitbucket_refresh_token
      )
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }

      case res.code
      when "200"
        body = JSON.parse(res.body)
        @user.update!(
          bitbucket_access_token: body["access_token"],
          bitbucket_refresh_token: body["refresh_token"],
          bitbucket_token_expires_at: Time.current + body["expires_in"].to_i.seconds
        )
      when "401"
        @user.update!(
          bitbucket_access_token: nil,
          bitbucket_refresh_token: nil,
          bitbucket_token_expires_at: nil
        )
        raise TokenRevoked, "Bitbucket refresh token rejected (revoked or expired)"
      else
        raise RefreshFailed, "Bitbucket token refresh returned #{res.code}"
      end
    end
  end
end

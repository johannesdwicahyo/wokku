require "net/http"
require "json"

module Gitlab
  class TokenRefresher
    class TokenRevoked < StandardError; end
    class RefreshFailed < StandardError; end

    OAUTH_URL = "https://gitlab.com/oauth/token"

    def initialize(user)
      @user = user
    end

    def refresh!
      uri = URI(OAUTH_URL)
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(
        "grant_type" => "refresh_token",
        "refresh_token" => @user.gitlab_refresh_token,
        "client_id" => ENV.fetch("GITLAB_OAUTH_CLIENT_ID"),
        "client_secret" => ENV.fetch("GITLAB_OAUTH_CLIENT_SECRET")
      )
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }

      case res.code
      when "200"
        body = JSON.parse(res.body)
        @user.update!(
          gitlab_access_token: body["access_token"],
          gitlab_refresh_token: body["refresh_token"],
          gitlab_token_expires_at: Time.current + body["expires_in"].to_i.seconds
        )
      when "401"
        @user.update!(
          gitlab_access_token: nil,
          gitlab_refresh_token: nil,
          gitlab_token_expires_at: nil
        )
        raise TokenRevoked, "GitLab refresh token rejected (revoked or expired)"
      else
        raise RefreshFailed, "GitLab token refresh returned #{res.code}"
      end
    end
  end
end

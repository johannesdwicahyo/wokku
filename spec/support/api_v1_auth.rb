# frozen_string_literal: true

# Shared helper for API v1 request specs: builds the Bearer auth header
# for a given user using ApiToken.create_with_token!.
module ApiV1AuthHelper
  def api_v1_token_for(user, name: "test", scope: "full")
    _, plain = ApiToken.create_with_token!(user: user, name: name, scope: scope)
    plain
  end

  def api_v1_headers(user_or_plain, json: false)
    plain = user_or_plain.is_a?(String) ? user_or_plain : api_v1_token_for(user_or_plain)
    h = { "Authorization" => "Bearer #{plain}" }
    h["Content-Type"] = "application/json" if json
    h
  end
end

RSpec.configure do |config|
  config.include ApiV1AuthHelper, type: :request
end

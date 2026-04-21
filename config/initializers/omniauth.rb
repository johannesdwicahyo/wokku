Rails.application.config.middleware.use OmniAuth::Builder do
  if ENV["GOOGLE_OAUTH_CLIENT_ID"].present?
    provider :google_oauth2,
      ENV["GOOGLE_OAUTH_CLIENT_ID"],
      ENV["GOOGLE_OAUTH_CLIENT_SECRET"],
      prompt: "select_account"
  end

  if ENV["GITHUB_OAUTH_CLIENT_ID"].present?
    provider :github,
      ENV["GITHUB_OAUTH_CLIENT_ID"],
      ENV["GITHUB_OAUTH_CLIENT_SECRET"],
      scope: "user:email"
  end

  # Apple Sign In — uncomment when credentials are ready
  # if ENV["APPLE_CLIENT_ID"].present?
  #   provider :apple,
  #     ENV["APPLE_CLIENT_ID"],
  #     "",
  #     scope: "email name",
  #     team_id: ENV["APPLE_TEAM_ID"],
  #     key_id: ENV["APPLE_KEY_ID"],
  #     pem: ENV["APPLE_PRIVATE_KEY"]
  # end
end

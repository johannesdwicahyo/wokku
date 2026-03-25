# OmniAuth configuration for GitHub and Google OAuth
Rails.application.config.middleware.use OmniAuth::Builder do
  if ENV["GITHUB_OAUTH_CLIENT_ID"].present?
    provider :github,
      ENV["GITHUB_OAUTH_CLIENT_ID"],
      ENV["GITHUB_OAUTH_CLIENT_SECRET"],
      scope: "user:email"
  end

  if ENV["GOOGLE_OAUTH_CLIENT_ID"].present?
    provider :google_oauth2,
      ENV["GOOGLE_OAUTH_CLIENT_ID"],
      ENV["GOOGLE_OAUTH_CLIENT_SECRET"]
  end
end

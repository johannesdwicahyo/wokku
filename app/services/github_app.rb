class GithubApp
  APP_ID = ENV["GITHUB_APP_ID"]
  PRIVATE_KEY = ENV["GITHUB_APP_PRIVATE_KEY"]
  WEBHOOK_SECRET = ENV["GITHUB_WEBHOOK_SECRET"]
  APP_SLUG = ENV.fetch("GITHUB_APP_SLUG", "wokku")

  class << self
    def installation_url
      "https://github.com/apps/#{APP_SLUG}/installations/new"
    end

    def configured?
      APP_ID.present? && PRIVATE_KEY.present?
    end

    def verify_webhook_signature(payload, signature, secret = WEBHOOK_SECRET)
      return false unless signature.present? && secret.present?
      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end

  def initialize(installation_id)
    @installation_id = installation_id
  end

  def client
    @client ||= Octokit::Client.new(access_token: installation_token)
  end

  def repos(per_page: 30, page: 1)
    app_client = Octokit::Client.new(bearer_token: jwt)
    app_client.list_app_installation_repositories(@installation_id, per_page: per_page, page: page)
  end

  def branches(repo_full_name)
    client.branches(repo_full_name).map(&:name)
  rescue Octokit::NotFound
    []
  end

  def repo(repo_full_name)
    client.repository(repo_full_name)
  rescue Octokit::NotFound
    nil
  end

  private

  def installation_token
    app_client = Octokit::Client.new(bearer_token: jwt)
    token = app_client.create_app_installation_access_token(@installation_id)
    token.token
  end

  def jwt
    private_key = OpenSSL::PKey::RSA.new(PRIVATE_KEY.gsub("\\n", "\n"))
    payload = {
      iat: Time.current.to_i - 60,
      exp: Time.current.to_i + (10 * 60),
      iss: APP_ID
    }
    JWT.encode(payload, private_key, "RS256")
  end
end

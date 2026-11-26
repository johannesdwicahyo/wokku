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

    # True only when GitHub says `repo_full_name` is installed under
    # `installation_id`. Asks as the App (JWT) — an installation token can read
    # any public repo, so it can't prove ownership. Fails closed on any error.
    def repo_owned_by_installation?(repo_full_name, installation_id)
      return false unless configured? && installation_id.present?
      return false unless repo_full_name.to_s.match?(%r{\A[A-Za-z0-9-]+/(?!\.\.?\z)[\w.-]+\z})

      app_client = Octokit::Client.new(bearer_token: jwt)
      app_client.find_repository_installation(repo_full_name).id.to_i == installation_id.to_i
    rescue Octokit::Error, Faraday::Error, JWT::EncodeError, OpenSSL::PKey::PKeyError, ArgumentError => e
      Rails.logger.warn("GithubApp: ownership check failed for #{repo_full_name}: #{e.class}")
      false
    end

    # App-level (not installation) credential, valid 10 minutes.
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

  def initialize(installation_id)
    @installation_id = installation_id
  end

  def client
    @client ||= Octokit::Client.new(access_token: installation_token)
  end

  # GET /installation/repositories: authenticates as the installation (its
  # token picks the installation), so it takes no installation id.
  def repos(per_page: 30, page: 1)
    client.list_app_installation_repositories(per_page: per_page, page: page)
  end

  def branches(repo_full_name)
    client.branches(repo_full_name).map(&:name)
  rescue Octokit::NotFound
    []
  end

  # Short-lived installation token (1h) — e.g. for `git fetch` of a private repo.
  def access_token
    installation_token
  end

  def repo(repo_full_name)
    client.repository(repo_full_name)
  rescue Octokit::NotFound
    nil
  end

  private

  def installation_token
    app_client = Octokit::Client.new(bearer_token: self.class.jwt)
    token = app_client.create_app_installation_access_token(@installation_id)
    token.token
  end
end

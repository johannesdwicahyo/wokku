require "test_helper"

class GitHubAppTest < ActiveSupport::TestCase
  test "installation_url returns correct URL" do
    url = GitHubApp.installation_url
    assert_includes url, "github.com/apps/"
  end

  test "verify_webhook_signature returns true for valid signature" do
    secret = "test_secret"
    payload = '{"action":"push"}'
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

    assert GitHubApp.verify_webhook_signature(payload, signature, secret)
  end

  test "verify_webhook_signature returns false for invalid signature" do
    refute GitHubApp.verify_webhook_signature("payload", "sha256=invalid", "secret")
  end
end

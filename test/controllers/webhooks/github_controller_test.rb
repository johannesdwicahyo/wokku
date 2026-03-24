require "test_helper"

class Webhooks::GithubControllerTest < ActionDispatch::IntegrationTest
  test "rejects unsigned webhook" do
    post "/webhooks/github", params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "accepts ping event" do
    payload = '{"zen":"test"}'
    secret = "test_secret"
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

    stub_const_value(GitHubApp, :WEBHOOK_SECRET, secret) do
      post "/webhooks/github",
        params: payload,
        headers: {
          "Content-Type" => "application/json",
          "X-GitHub-Event" => "ping",
          "X-Hub-Signature-256" => signature
        }
      assert_response :ok
    end
  end
end

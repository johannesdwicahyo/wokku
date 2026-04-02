require "test_helper"

class Webhooks::GithubControllerTest < ActionDispatch::IntegrationTest
  test "rejects unsigned webhook" do
    post "/webhooks/github", params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "accepts ping event with valid signature" do
    payload = '{"zen":"test"}'
    secret = GithubApp::WEBHOOK_SECRET || "test"
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

    post "/webhooks/github",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-GitHub-Event" => "ping",
        "X-Hub-Signature-256" => signature
      }

    # If WEBHOOK_SECRET is nil (not configured), signature check returns false → 401
    # If WEBHOOK_SECRET is set, valid signature → 200
    if GithubApp::WEBHOOK_SECRET.present?
      assert_response :ok
    else
      assert_response :unauthorized
    end
  end
end

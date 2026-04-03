require "test_helper"

class GithubAppTest < ActiveSupport::TestCase
  test "installation_url returns correct URL" do
    url = GithubApp.installation_url
    assert_includes url, "github.com/apps/"
  end

  test "configured? returns false when APP_ID is not set" do
    original_id = GithubApp::APP_ID
    original_key = GithubApp::PRIVATE_KEY

    GithubApp.send(:remove_const, :APP_ID)
    GithubApp.const_set(:APP_ID, nil)

    assert_not GithubApp.configured?
  ensure
    GithubApp.send(:remove_const, :APP_ID)
    GithubApp.const_set(:APP_ID, original_id)
  end

  test "configured? returns true when both APP_ID and PRIVATE_KEY are set" do
    original_id = GithubApp::APP_ID
    original_key = GithubApp::PRIVATE_KEY

    GithubApp.send(:remove_const, :APP_ID)
    GithubApp.send(:remove_const, :PRIVATE_KEY)
    GithubApp.const_set(:APP_ID, "12345")
    GithubApp.const_set(:PRIVATE_KEY, "FAKE_KEY")

    assert GithubApp.configured?
  ensure
    GithubApp.send(:remove_const, :APP_ID)
    GithubApp.send(:remove_const, :PRIVATE_KEY)
    GithubApp.const_set(:APP_ID, original_id)
    GithubApp.const_set(:PRIVATE_KEY, original_key)
  end

  test "verify_webhook_signature returns true for valid signature" do
    secret = "test_secret"
    payload = '{"action":"push"}'
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

    assert GithubApp.verify_webhook_signature(payload, signature, secret)
  end

  test "verify_webhook_signature returns false for invalid signature" do
    refute GithubApp.verify_webhook_signature("payload", "sha256=invalid", "secret")
  end

  test "verify_webhook_signature returns false when signature is nil" do
    refute GithubApp.verify_webhook_signature("payload", nil, "secret")
  end

  test "verify_webhook_signature returns false when secret is nil" do
    refute GithubApp.verify_webhook_signature("payload", "sha256=whatever", nil)
  end

  test "verify_webhook_signature returns false for wrong hmac" do
    secret = "correct_secret"
    payload = '{"action":"push"}'
    wrong_signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "wrong_secret", payload)

    refute GithubApp.verify_webhook_signature(payload, wrong_signature, secret)
  end

  test "APP_SLUG defaults to wokku" do
    assert_equal "wokku", GithubApp::APP_SLUG
  end

  test "installation_url includes app slug" do
    slug = GithubApp::APP_SLUG
    url = GithubApp.installation_url
    assert_includes url, slug
  end

  test "branches returns empty array when Octokit raises NotFound" do
    github = GithubApp.new(123)
    github.define_singleton_method(:client) do
      mock = Object.new
      mock.define_singleton_method(:branches) { |_repo| raise Octokit::NotFound }
      mock
    end

    result = github.branches("nonexistent/repo")
    assert_equal [], result
  end

  test "repo returns nil when Octokit raises NotFound" do
    github = GithubApp.new(123)
    github.define_singleton_method(:client) do
      mock = Object.new
      mock.define_singleton_method(:repository) { |_repo| raise Octokit::NotFound }
      mock
    end

    result = github.repo("nonexistent/repo")
    assert_nil result
  end
end

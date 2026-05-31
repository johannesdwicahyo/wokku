require "rails_helper"

RSpec.describe Gitlab::TokenRefresher do
  let(:user) do
    create(:user,
           gitlab_access_token: "stale_token",
           gitlab_refresh_token: "refresh_xyz",
           gitlab_token_expires_at: 5.minutes.ago)
  end

  before do
    ENV["GITLAB_OAUTH_CLIENT_ID"] ||= "test_client_id"
    ENV["GITLAB_OAUTH_CLIENT_SECRET"] ||= "test_client_secret"
  end

  describe "#refresh!" do
    it "POSTs to the GitLab oauth/token endpoint and updates the user" do
      stub_request(:post, "https://gitlab.com/oauth/token")
        .with(body: hash_including(
          "grant_type" => "refresh_token",
          "refresh_token" => "refresh_xyz"
        ))
        .to_return(
          status: 200,
          body: {
            access_token: "fresh_token",
            refresh_token: "new_refresh",
            expires_in: 7200
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      described_class.new(user).refresh!

      expect(user.reload.gitlab_access_token).to eq("fresh_token")
      expect(user.gitlab_refresh_token).to eq("new_refresh")
      expect(user.gitlab_token_expires_at).to be_within(5.seconds).of(7200.seconds.from_now)
    end

    it "raises TokenRevoked and nulls the user's tokens on a 401" do
      stub_request(:post, "https://gitlab.com/oauth/token").to_return(status: 401)

      expect { described_class.new(user).refresh! }.to raise_error(Gitlab::TokenRefresher::TokenRevoked)

      expect(user.reload.gitlab_access_token).to be_nil
      expect(user.gitlab_refresh_token).to be_nil
    end

    it "raises RefreshFailed on transient 5xx (no token nulling)" do
      stub_request(:post, "https://gitlab.com/oauth/token").to_return(status: 502)

      expect { described_class.new(user).refresh! }.to raise_error(Gitlab::TokenRefresher::RefreshFailed)

      expect(user.reload.gitlab_access_token).to eq("stale_token")
    end
  end
end

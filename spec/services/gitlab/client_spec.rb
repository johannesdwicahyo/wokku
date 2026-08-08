require "rails_helper"

RSpec.describe Gitlab::Client do
  let(:user) do
    create(:user,
           gitlab_access_token: "fresh_token",
           gitlab_refresh_token: "refresh_xyz",
           gitlab_token_expires_at: 1.hour.from_now)
  end

  describe "#add_comment" do
    it "POSTs to the MR notes endpoint and returns the comment id" do
      stub_request(:post, "https://gitlab.com/api/v4/projects/octo%2Frepo/merge_requests/7/notes")
        .with(headers: { "Authorization" => "Bearer fresh_token" }, body: hash_including("body" => "hello"))
        .to_return(status: 201, body: { id: 999, body: "hello" }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new(user).add_comment("octo/repo", 7, "hello")

      expect(result.id).to eq(999)
    end
  end

  describe "#update_comment" do
    it "PUTs to the MR note endpoint" do
      stub_request(:put, "https://gitlab.com/api/v4/projects/octo%2Frepo/merge_requests/7/notes/999")
        .with(headers: { "Authorization" => "Bearer fresh_token" })
        .to_return(status: 200, body: { id: 999, body: "updated" }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(user).update_comment("octo/repo", 7, 999, "updated")
    end
  end

  describe "lazy refresh" do
    it "refreshes the token before making a call when expired" do
      user.update!(gitlab_token_expires_at: 30.seconds.from_now) # inside the 60s safety window
      refresher = instance_double(Gitlab::TokenRefresher, refresh!: true)
      allow(Gitlab::TokenRefresher).to receive(:new).with(user).and_return(refresher)
      expect(refresher).to receive(:refresh!)

      stub_request(:post, %r{gitlab.com/api/v4/projects/.*/merge_requests/.*/notes})
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(user).add_comment("octo/repo", 7, "hi")
    end

    it "does NOT refresh when token is fresh" do
      expect(Gitlab::TokenRefresher).not_to receive(:new)

      stub_request(:post, %r{gitlab.com/api/v4/projects/.*/merge_requests/.*/notes})
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(user).add_comment("octo/repo", 7, "hi")
    end
  end

  describe "non-2xx response" do
    it "raises ApiError with status" do
      stub_request(:post, %r{gitlab.com/api/v4/projects/.*})
        .to_return(status: 403, body: "")

      expect { described_class.new(user).add_comment("octo/repo", 7, "hi") }
        .to raise_error(Gitlab::Client::ApiError) { |e| expect(e.status).to eq(403) }
    end
  end
end

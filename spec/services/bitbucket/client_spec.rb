require "rails_helper"

RSpec.describe Bitbucket::Client do
  let(:user) do
    create(:user,
           bitbucket_access_token: "fresh_token",
           bitbucket_refresh_token: "refresh_xyz",
           bitbucket_token_expires_at: 1.hour.from_now)
  end

  describe "#add_comment" do
    it "POSTs JSON to the pullrequest comments endpoint and returns the comment id" do
      stub_request(:post, "https://api.bitbucket.org/2.0/repositories/octo/repo/pullrequests/7/comments")
        .with(
          headers: {
            "Authorization" => "Bearer fresh_token",
            "Content-Type" => "application/json"
          },
          body: { content: { raw: "hello" } }.to_json
        )
        .to_return(status: 201, body: { id: 999, content: { raw: "hello" } }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new(user).add_comment("octo/repo", 7, "hello")

      expect(result.id).to eq(999)
    end
  end

  describe "#update_comment" do
    it "PUTs JSON to the comment endpoint" do
      stub_request(:put, "https://api.bitbucket.org/2.0/repositories/octo/repo/pullrequests/7/comments/999")
        .with(
          headers: { "Authorization" => "Bearer fresh_token", "Content-Type" => "application/json" },
          body: { content: { raw: "updated" } }.to_json
        )
        .to_return(status: 200, body: { id: 999 }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(user).update_comment("octo/repo", 7, 999, "updated")
    end
  end

  describe "lazy refresh" do
    it "refreshes the token before making a call when expired" do
      user.update!(bitbucket_token_expires_at: 30.seconds.from_now)
      refresher = instance_double(Bitbucket::TokenRefresher, refresh!: true)
      allow(Bitbucket::TokenRefresher).to receive(:new).with(user).and_return(refresher)
      expect(refresher).to receive(:refresh!)

      stub_request(:post, %r{api.bitbucket.org/2.0/repositories/.*/pullrequests/.*/comments})
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(user).add_comment("octo/repo", 7, "hi")
    end

    it "does NOT refresh when token is fresh" do
      expect(Bitbucket::TokenRefresher).not_to receive(:new)

      stub_request(:post, %r{api.bitbucket.org/2.0/repositories/.*/pullrequests/.*/comments})
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(user).add_comment("octo/repo", 7, "hi")
    end
  end

  describe "non-2xx response" do
    it "raises ApiError with status" do
      stub_request(:post, %r{api.bitbucket.org/.*})
        .to_return(status: 403, body: "")

      expect { described_class.new(user).add_comment("octo/repo", 7, "hi") }
        .to raise_error(Bitbucket::Client::ApiError) { |e| expect(e.status).to eq(403) }
    end
  end
end

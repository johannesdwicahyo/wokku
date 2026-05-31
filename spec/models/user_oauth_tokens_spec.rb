require "rails_helper"

RSpec.describe User, "OAuth token columns" do
  it "encrypts gitlab_access_token" do
    user = create(:user)
    user.update!(gitlab_access_token: "glpat_secret_xyz")
    raw = User.connection.select_value("SELECT gitlab_access_token FROM users WHERE id = '#{user.id}'")
    expect(raw).not_to include("glpat_secret_xyz")
    expect(user.reload.gitlab_access_token).to eq("glpat_secret_xyz")
  end

  it "encrypts bitbucket_access_token" do
    user = create(:user)
    user.update!(bitbucket_access_token: "bb_secret_abc")
    raw = User.connection.select_value("SELECT bitbucket_access_token FROM users WHERE id = '#{user.id}'")
    expect(raw).not_to include("bb_secret_abc")
    expect(user.reload.bitbucket_access_token).to eq("bb_secret_abc")
  end

  describe "#gitlab_token_expired?" do
    it "is true when expires_at is past" do
      user = create(:user, gitlab_access_token: "x", gitlab_token_expires_at: 1.minute.ago)
      expect(user.gitlab_token_expired?).to be(true)
    end

    it "is false when expires_at is in the future" do
      user = create(:user, gitlab_access_token: "x", gitlab_token_expires_at: 10.minutes.from_now)
      expect(user.gitlab_token_expired?).to be(false)
    end

    it "treats a token expiring within the 60s safety window as expired" do
      user = create(:user, gitlab_access_token: "x", gitlab_token_expires_at: 30.seconds.from_now)
      expect(user.gitlab_token_expired?).to be(true)
    end

    it "is true when access_token is nil" do
      user = create(:user, gitlab_access_token: nil)
      expect(user.gitlab_token_expired?).to be(true)
    end
  end
end

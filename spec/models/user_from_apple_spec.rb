require "rails_helper"

RSpec.describe "User.from_apple" do
  def claims(**over)
    { "sub" => "001.apple", "email" => "jane@example.com", "email_verified" => true }.merge(over.transform_keys(&:to_s))
  end

  it "finds a user by apple_uid first" do
    user = create(:user, email: "other@example.com", apple_uid: "001.apple")
    expect(User.from_apple(claims)).to eq(user)
  end

  it "links an existing GitHub account by verified email without touching provider/uid" do
    user = create(:user, email: "jane@example.com", provider: "github", uid: "42", email_provider_verified: true)
    expect(User.from_apple(claims)).to eq(user)
    user.reload
    expect([ user.apple_uid, user.provider, user.uid ]).to eq([ "001.apple", "github", "42" ])
  end

  it "treats the string \"true\" as verified (web id_token)" do
    user = create(:user, email: "jane@example.com", email_provider_verified: true)
    expect(User.from_apple(claims(email_verified: "true"))).to eq(user)
  end

  it "never links on an unverified email" do
    create(:user, email: "jane@example.com")
    result = User.from_apple(claims(email_verified: "false"))
    expect(result).not_to be_persisted
  end

  it "creates a new account for a relay address" do
    result = User.from_apple(claims(email: "x1@privaterelay.appleid.com", is_private_email: true), name: "Jane D")
    expect(result).to be_persisted
    expect([ result.apple_uid, result.provider, result.uid, result.name ]).to eq([ "001.apple", "apple", "001.apple", "Jane D" ])
  end

  it "downcases the email before matching" do
    user = create(:user, email: "jane@example.com", email_provider_verified: true)
    expect(User.from_apple(claims(email: "Jane@Example.com"))).to eq(user)
  end

  it "refuses when there is no apple_uid match and no email" do
    expect(User.from_apple(claims(email: nil))).not_to be_persisted
  end

  it "refuses a blank sub" do
    expect(User.from_apple(claims(sub: ""))).not_to be_persisted
  end

  it "refuses new accounts on closed registration" do
    allow(Wokku.config).to receive(:open_registration).and_return(false)
    expect(User.from_apple(claims)).not_to be_persisted
  end

  it "still links an existing account on closed registration" do
    allow(Wokku.config).to receive(:open_registration).and_return(false)
    user = create(:user, email: "jane@example.com", email_provider_verified: true)
    expect(User.from_apple(claims)).to eq(user)
  end

  it "refuses to link a verified-email match whose email was never provider-verified" do
    user = create(:user, email: "jane@example.com", email_provider_verified: false)
    expect(User.from_apple(claims)).not_to be_persisted
    expect(user.reload.apple_uid).to be_nil
  end

  it "marks accounts created from Apple as provider-verified" do
    expect(User.from_apple(claims(email: "x1@privaterelay.appleid.com")).email_provider_verified).to be(true)
  end

  it "clears the flag when an existing user's email changes" do
    user = create(:user, email_provider_verified: true)
    user.update!(email: "changed@example.com")
    expect(user.reload.email_provider_verified).to be(false)
  end

  it "keeps an explicit flag written in the same save as an email change" do
    user = create(:user, email_provider_verified: false)
    user.update!(email: "changed@example.com", email_provider_verified: true)
    expect(user.reload.email_provider_verified).to be(true)
  end

  context "admin email" do
    let(:admin_claims) { claims(email: User::ADMIN_EMAIL) }

    it "links to the seeded admin on a verified email" do
      admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
      expect(User.from_apple(admin_claims)).to eq(admin)
    end

    it "never links the admin on an unverified email" do
      User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
      expect(User.from_apple(admin_claims.merge("email_verified" => false))).not_to be_persisted
    end
  end

  it "never re-links an account already linked to a different apple_uid" do
    user = create(:user, email: "jane@example.com", apple_uid: "A", email_provider_verified: true)
    expect(User.from_apple(claims(sub: "B"))).not_to be_persisted
    expect(user.reload.apple_uid).to eq("A")
  end

  it "never re-links the admin already linked to a different apple_uid" do
    admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
    admin.update_columns(apple_uid: "A")
    expect(User.from_apple(claims(sub: "B", email: User::ADMIN_EMAIL))).not_to be_persisted
    expect(admin.reload.apple_uid).to eq("A")
  end

  it "stores the refresh token encrypted with its client id" do
    user = create(:user)
    # Long token: a 2-char one can appear by chance inside the random ciphertext.
    token = "apple-refresh-token-plaintext-marker"
    user.remember_apple_refresh_token!(token, client_id: "cloud.wokku.app")
    user.reload
    expect([ user.apple_refresh_token, user.apple_token_client_id ]).to eq([ token, "cloud.wokku.app" ])
    raw = User.connection.select_value("SELECT apple_refresh_token FROM users WHERE id = #{User.connection.quote(user.id)}")
    expect(raw).not_to include(token)
  end
end

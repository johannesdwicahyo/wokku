require "rails_helper"

RSpec.describe "GET /mobile/auth/start", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:state) { "s" * 24 }
  let(:challenge) { "c" * 43 }
  let(:params) { { state: state, code_challenge: challenge, code_challenge_method: "S256" } }
  let(:user) { create(:user) }

  it "sends a signed-out user to sign in and remembers where to come back" do
    get "/mobile/auth/start", params: params
    expect(response).to redirect_to(new_user_session_path)
    back = URI(session["user_return_to"])
    expect(back.path).to eq("/mobile/auth/start")
    expect(Rack::Utils.parse_query(back.query)).to eq(params.stringify_keys)
  end

  it "completes the round trip after sign-in" do
    get "/mobile/auth/start", params: params
    sign_in user
    get session["user_return_to"]
    expect(response).to have_http_status(:found)
    expect(response.headers["Cache-Control"]).to include("no-store")
    loc = URI(response.location)
    expect([ loc.scheme, loc.host ]).to eq([ "wokku", "auth" ])
    q = Rack::Utils.parse_query(loc.query)
    expect(q["state"]).to eq(state)
    expect(MobileAuthCode.find_by(code_digest: MobileAuthCode.digest(q["code"])).user).to eq(user)
  end

  it "issues a fresh single code for a signed-in user" do
    sign_in user
    expect { get "/mobile/auth/start", params: params }.to change(MobileAuthCode, :count).by(1)
    expect(MobileAuthCode.last.code_challenge).to eq(challenge)
  end

  it "refuses an admin without two-factor" do
    admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
    admin.update_column(:otp_required_for_login, false)
    sign_in admin
    get "/mobile/auth/start", params: params
    expect(response).to have_http_status(:forbidden)
    expect(MobileAuthCode.count).to eq(0)
  end

  [
    { state: "short" },
    { code_challenge: "too-short" },
    { code_challenge_method: "plain" },
    { state: "bad state with spaces!!!!" }
  ].each do |bad|
    it "400s on #{bad.keys.first}=#{bad.values.first.inspect}" do
      sign_in user
      get "/mobile/auth/start", params: params.merge(bad)
      expect(response).to have_http_status(:bad_request)
      expect(MobileAuthCode.count).to eq(0)
    end
  end
end

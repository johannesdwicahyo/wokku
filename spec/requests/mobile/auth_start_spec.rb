require "rails_helper"

RSpec.describe "Mobile web sign-in handoff", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:state) { "s" * 24 }
  let(:challenge) { "c" * 43 }
  let(:params) { { state: state, code_challenge: challenge, code_challenge_method: "S256" } }
  let(:user) { create(:user) }

  def expect_wokku_redirect
    expect(response).to have_http_status(:found)
    loc = URI(response.location)
    expect([ loc.scheme, loc.host ]).to eq([ "wokku", "auth" ])
    q = Rack::Utils.parse_query(loc.query)
    expect(q["state"]).to eq(state)
    MobileAuthCode.find_by(code_digest: MobileAuthCode.digest(q["code"]))
  end

  describe "GET /mobile/auth/start" do
    it "sends a signed-out user to sign in and remembers where to come back" do
      get "/mobile/auth/start", params: params
      expect(response).to redirect_to(new_user_session_path)
      back = URI(session["user_return_to"])
      expect(back.path).to eq("/mobile/auth/start")
      expect(Rack::Utils.parse_query(back.query)).to eq(params.stringify_keys)
    end

    it "shows a confirmation page for a signed-in user and issues no code" do
      sign_in user
      expect { get "/mobile/auth/start", params: params }.not_to change(MobileAuthCode, :count)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include("Sign in to the Wokku app", "Continue as #{user.email}", "Not you?",
                                       %(action="/mobile/auth/confirm"), %(value="#{state}"), %(value="#{challenge}"))
    end

    it "refuses an admin without two-factor" do
      admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
      admin.update_column(:otp_required_for_login, false)
      sign_in admin
      get "/mobile/auth/start", params: params
      expect(response).to have_http_status(:forbidden)
      expect(MobileAuthCode.count).to eq(0)
    end

    it "shows a deletion-pending user how to cancel and issues no code" do
      user.update!(deletion_scheduled_at: 2.days.from_now)
      sign_in user
      get "/mobile/auth/start", params: params
      expect(response.body).to include("scheduled for deletion", "Then return to the Wokku app",
                                       %(action="/dashboard/account_deletion"))
      expect(response.body).not_to include("/mobile/auth/confirm")
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
      end
    end
  end

  describe "POST /mobile/auth/confirm" do
    it "issues one code and redirects to wokku://" do
      sign_in user
      expect { post "/mobile/auth/confirm", params: params }.to change(MobileAuthCode, :count).by(1)
      expect(response.headers["Cache-Control"]).to include("no-store")
      rec = expect_wokku_redirect
      expect([ rec.user, rec.code_challenge ]).to eq([ user, challenge ])
    end

    [
      { state: "short" },
      { code_challenge: "too-short" },
      { code_challenge_method: "plain" }
    ].each do |bad|
      it "400s on #{bad.keys.first}=#{bad.values.first.inspect} and issues no code" do
        sign_in user
        post "/mobile/auth/confirm", params: params.merge(bad)
        expect(response).to have_http_status(:bad_request)
        expect(MobileAuthCode.count).to eq(0)
      end
    end

    it "refuses a signed-out request" do
      post "/mobile/auth/confirm", params: params
      expect(response).to have_http_status(:unauthorized)
      expect(MobileAuthCode.count).to eq(0)
    end

    it "refuses an admin without two-factor" do
      admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
      admin.update_column(:otp_required_for_login, false)
      sign_in admin
      post "/mobile/auth/confirm", params: params
      expect(response).to have_http_status(:forbidden)
      expect(MobileAuthCode.count).to eq(0)
    end

    it "refuses a deletion-pending user" do
      user.update!(deletion_scheduled_at: 2.days.from_now)
      sign_in user
      post "/mobile/auth/confirm", params: params
      expect(response).to have_http_status(:forbidden)
      expect(MobileAuthCode.count).to eq(0)
    end

    it "rejects a POST without a CSRF token" do
      ActionController::Base.allow_forgery_protection = true
      sign_in user
      post "/mobile/auth/confirm", params: params
      expect(response).not_to have_http_status(:found)
      expect(MobileAuthCode.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  it "completes the round trip: start signed out → sign in → confirm page → POST → wokku://" do
    get "/mobile/auth/start", params: params
    sign_in user
    get session["user_return_to"]
    expect(response.body).to include("Continue as #{user.email}")
    post "/mobile/auth/confirm", params: params
    expect(expect_wokku_redirect.user).to eq(user)
  end
end

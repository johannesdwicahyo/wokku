# frozen_string_literal: true

require "rails_helper"

# Security review fix wave for the 2FA enforcement (d93f853).
RSpec.describe "2FA hardening", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:password) { "supersecret123" }
  let(:user) do
    create(:user, :with_personal_team, otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end
  let(:max) { Devise.maximum_attempts }

  def with_csrf
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = old
  end

  def csrf_token
    get new_user_session_path
    # The session-wide meta token: per-form tokens on the page may belong to
    # OAuth buttons (when a provider's env is set) and are invalid here.
    response.body[/<meta name="csrf-token" content="([^"]+)"/, 1] || raise("no token")
  end

  describe "C1: API login" do
    it "does not let an array email reach a user (no IN lookup)" do
      post api_v1_auth_login_path, params: { email: [ user.email, "junk@x.test" ], password: password, otp_code: user.current_otp }
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Invalid email or password")
    end

    it "refuses a locked user even with a valid code" do
      user.lock_access!(send_instructions: false)
      expect {
        post api_v1_auth_login_path, params: { email: user.email, password: password, otp_code: user.current_otp }
      }.not_to change(ApiToken, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a soft-deleted user" do
      plain = create(:user, :hard_deleted)
      post api_v1_auth_login_path, params: { email: plain.email, password: password }
      expect(response).to have_http_status(:unauthorized)
    end

    it "counts wrong codes toward lockout and locks the account" do
      max.times { post api_v1_auth_login_path, params: { email: user.email, password: password, otp_code: "000000" } }
      expect(user.reload).to be_access_locked
      post api_v1_auth_login_path, params: { email: user.email, password: password, otp_code: user.current_otp }
      expect(response).to have_http_status(:unauthorized)
    end

    it "resets failed_attempts after a full success" do
      user.update_columns(failed_attempts: 3)
      post api_v1_auth_login_path, params: { email: user.email, password: password, otp_code: user.current_otp }
      expect(response).to have_http_status(:created)
      expect(user.reload.failed_attempts).to eq(0)
    end
  end

  describe "C2: codes page under Turbo" do
    before { sign_in user }

    it "opts the enable/regenerate/disable forms out of Turbo Drive" do
      user.update!(otp_required_for_login: false)
      get "/dashboard/two_factor"
      expect(response.body).to match(%r{<form[^>]*data-turbo="false"[^>]*action="/dashboard/two_factor/enable"|<form[^>]*action="/dashboard/two_factor/enable"[^>]*data-turbo="false"})
      user.update!(otp_required_for_login: true)
      get "/dashboard/two_factor"
      %w[regenerate_codes disable].each do |a|
        expect(response.body).to match(%r{<form(?=[^>]*data-turbo="false")(?=[^>]*action="/dashboard/two_factor/#{a}")})
      end
    end

    it "serves the codes no-store and out of Turbo's cache" do
      post "/dashboard/two_factor/regenerate_codes", params: { otp_code: user.current_otp }
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include('<meta name="turbo-cache-control" content="no-cache">')
    end
  end

  describe "I1: password interception needs a valid CSRF token" do
    around { |ex| with_csrf { ex.run } }

    it "does not reveal a correct password without a CSRF token" do
      post user_session_path, params: { user: { email: user.email, password: password } }
      expect(response).not_to redirect_to(users_two_factor_path)
      expect(session[:two_factor_user_id]).to be_nil
    end

    it "counts a wrong password exactly once with a valid token" do
      token = csrf_token
      expect {
        post user_session_path, params: { authenticity_token: token, user: { email: user.email, password: "wrong-pass" } }
      }.to change { user.reload.failed_attempts }.by(1)
    end

    it "challenges with a valid token and the right password" do
      token = csrf_token
      post user_session_path, params: { authenticity_token: token, user: { email: user.email, password: password } }
      expect(response).to redirect_to(users_two_factor_path)
    end
  end

  describe "I3: dashboard regenerate/disable go through lockable" do
    let(:member) do
      create(:user, :with_personal_team, otp_secret: User.generate_otp_secret, otp_required_for_login: true)
    end

    before { sign_in member }

    it "counts wrong regenerate codes and locks" do
      expect {
        post "/dashboard/two_factor/regenerate_codes", params: { otp_code: "000000" }
      }.to change { member.reload.failed_attempts }.by(1)
      member.update_columns(failed_attempts: max - 1)
      post "/dashboard/two_factor/regenerate_codes", params: { otp_code: "000000" }
      expect(member.reload).to be_access_locked
    end

    it "counts wrong disable codes" do
      expect {
        delete "/dashboard/two_factor/disable", params: { otp_code: "000000" }
      }.to change { member.reload.failed_attempts }.by(1)
      expect(member.reload.two_factor_enabled?).to be true
    end
  end

  describe "M4: enable with 2FA already on" do
    it "does not rotate the secret" do
      sign_in user
      expect {
        post "/dashboard/two_factor/enable", params: { otp_code: "000000" }
      }.not_to change { user.reload.otp_secret }
      expect(response).to redirect_to("/dashboard/two_factor")
    end
  end

  describe "M6: interception reads the params Devise reads" do
    it "challenges the user Devise would authenticate when query and body disagree" do
      other = create(:user)
      q = { user: { email: other.email, password: "wrong-pass" } }.to_query
      post "#{user_session_path}?#{q}", params: { user: { email: user.email, password: password, otp_attempt: user.current_otp } }
      expect(response).to redirect_to(users_two_factor_path)
      get "/dashboard/apps"
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "M3: challenge throttle" do
    before do
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.reset!
    end

    after do
      Rack::Attack.enabled = false
      Rack::Attack.reset!
    end

    it "throttles bursts of challenge posts per IP" do
      statuses = Array.new(11) do
        post users_two_factor_path, params: { code: "1" }, env: { "REMOTE_ADDR" => "10.7.7.7" }
        response.status
      end
      expect(statuses.last).to eq(429)
    end

    it "throttles bursts per pending user across IPs" do
      post user_session_path, params: { user: { email: user.email, password: password } }
      statuses = Array.new(6) do |i|
        post users_two_factor_path, params: { code: "000000" }, env: { "REMOTE_ADDR" => "10.8.8.#{i}" }
        response.status
      end
      expect(statuses.last).to eq(429)
    end
  end

  describe "M9" do
    it "warns on the dashboard when no recovery codes remain" do
      sign_in user
      get "/dashboard/apps"
      expect(response.body).to include(I18n.t("auth.two_factor.no_codes_banner"))
      user.generate_otp_backup_codes!
      user.save!
      get "/dashboard/apps"
      expect(response.body).not_to include(I18n.t("auth.two_factor.no_codes_banner"))
    end

    it "does not tell a deleted account it is locked at the challenge" do
      post user_session_path, params: { user: { email: user.email, password: password } }
      user.update_columns(deleted_at: Time.current)
      post users_two_factor_path, params: { code: user.current_otp }
      expect(flash[:alert]).not_to eq(I18n.t("devise.failure.locked"))
      expect(flash[:alert]).to eq(I18n.t("devise.failure.account_deleted"))
    end
  end

  describe "M8: self-host log filtering" do
    it "filters 2FA codes and passwords" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      out = filter.filter("code" => "a", "otp_code" => "b", "otp_attempt" => "c", "password" => "d", "state" => "ok")
      expect(out.values_at("code", "otp_code", "otp_attempt", "password")).to all(eq("[FILTERED]"))
      expect(out["state"]).to eq("ok")
    end
  end
end

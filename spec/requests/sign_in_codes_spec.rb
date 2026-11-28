# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email sign-in code", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:siteverify) { "https://challenges.cloudflare.com/turnstile/v0/siteverify" }

  around do |ex|
    Wokku.configure { |c| c.email_sign_in = true }
    ex.run
  ensure
    Wokku.configure { |c| c.email_sign_in = nil; c.turnstile_site_key = nil; c.turnstile_secret_key = nil }
  end

  def request_code(email, code: "123456", **params)
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(code.to_i)
    post users_sign_in_codes_path, params: { email: email, **params }
  end

  def verify(code) = post(verify_users_sign_in_code_path, params: { code: code })

  describe "flag off" do
    it "404s every route" do
      Wokku.configure { |c| c.email_sign_in = false }
      post users_sign_in_codes_path, params: { email: user.email }
      expect(response).to have_http_status(:not_found)
      get users_sign_in_code_path
      expect(response).to have_http_status(:not_found)
      post verify_users_sign_in_code_path, params: { code: "123456" }
      expect(response).to have_http_status(:not_found)
      post resend_users_sign_in_code_path
      expect(response).to have_http_status(:not_found)
      expect(SignInCode.count).to eq(0)
    end
  end

  describe "step 1" do
    it "answers the same for an unknown, a suspended and an active email; mails only the active one" do
      suspended = create(:user, abuse_suspended_at: Time.current)
      answers = {}
      { unknown: "nobody-#{SecureRandom.hex(3)}@example.com", suspended: suspended.email }.each do |kind, email|
        Wokku.configure { |c| c.open_registration = false } if kind == :unknown # unknown + closed = no mail
        expect { request_code(email) }.not_to have_enqueued_mail(SignInCodeMailer, :code)
        answers[kind] = [ response.status, response.location, flash[:notice], flash[:alert] ]
        Wokku.configure { |c| c.open_registration = true }
      end
      expect { request_code(user.email) }.to have_enqueued_mail(SignInCodeMailer, :code)
      answers[:active] = [ response.status, response.location, flash[:notice], flash[:alert] ]

      expect(answers.values.uniq.size).to eq(1)
      expect(response).to redirect_to(users_sign_in_code_path)
      expect(response.location).not_to include(CGI.escape(user.email))
    ensure
      Wokku.configure { |c| c.open_registration = true }
    end

    it "re-renders step 1 with the format error for a bad email, sending nothing" do
      expect { request_code("not-an-email") }.not_to change(SignInCode, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("sign_in_codes.invalid_email")))
      expect(session[:sign_in_code_email]).to be_nil
    end

    it "keeps the email out of the URL and in the session, normalised" do
      request_code(" #{user.email.upcase} ")
      expect(session[:sign_in_code_email]).to eq(user.email)
      expect(response.location).not_to include("@")
    end

    it "redirects a signed-in user away" do
      sign_in user
      post users_sign_in_codes_path, params: { email: user.email }
      expect(response).to have_http_status(:redirect)
      expect(SignInCode.count).to eq(0)
    end
  end

  describe "step 2" do
    it "redirects to sign-in with no pending email" do
      get users_sign_in_code_path
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to eq(I18n.t("sign_in_codes.start_again"))
    end

    it "redirects to sign-in once the pending email is 10 minutes old" do
      request_code(user.email)
      travel 10.minutes + 1.second do
        get users_sign_in_code_path
        expect(response).to redirect_to(new_user_session_path)
        expect(session[:sign_in_code_email]).to be_nil
      end
    end

    it "renders the code form with the pending email" do
      request_code(user.email)
      get users_sign_in_code_path
      expect(response).to have_http_status(:ok)
      input = Nokogiri::HTML(response.body).at_css("input[name='code']")
      expect(input.attributes.transform_values(&:value)).to include(
        "inputmode" => "numeric", "autocomplete" => "one-time-code", "maxlength" => "6", "pattern" => "[0-9]{6}"
      )
      expect(response.body).to include(user.email)
    end
  end

  describe "verify" do
    it "signs a non-2FA user in (Devise's after-sign-in path, as OAuth)" do
      request_code(user.email, code: "424242")
      verify("424242")
      expect(response).to redirect_to(root_path)
      expect(session[:sign_in_code_email]).to be_nil
      get "/dashboard/apps"
      expect(response).to have_http_status(:ok)
    end

    it "sends an admin with TOTP to the 2FA challenge, not signed in yet" do
      admin = users(:admin)
      request_code(admin.email, code: "424242")
      verify("424242")
      expect(response).to redirect_to(users_two_factor_path)
      expect(session[:two_factor_user_id]).to eq(admin.id)
      get "/dashboard/apps"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "creates a new account and flags the sign-up like OAuth does" do
      email = "fresh-#{SecureRandom.hex(3)}@example.com"
      request_code(email, code: "424242")
      expect { verify("424242") }.to change(User, :count).by(1)
      expect(flash[:posthog_event]).to eq("signup_completed")
      expect(flash[:posthog_props].stringify_keys).to eq("provider" => "email")
    end

    it "re-renders step 2 with 422 on a wrong code" do
      request_code(user.email, code: "424242")
      verify("000000")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("sign_in_codes.mismatch")))
    end

    it "gives the locked copy on the 6th try" do
      request_code(user.email, code: "424242")
      5.times { verify("000000") }
      verify("424242")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("sign_in_codes.locked")))
    end
  end

  describe "resend" do
    it "gives the cooldown notice within 45 s" do
      request_code(user.email)
      travel 10.seconds do
        expect { post resend_users_sign_in_code_path }.not_to have_enqueued_mail(SignInCodeMailer, :code)
        expect(response).to redirect_to(users_sign_in_code_path)
        expect(flash[:notice]).to match(/\AWait \d+ s before asking for another code\.\z/)
      end
    end

    it "sends a new code after 45 s" do
      request_code(user.email)
      travel 46.seconds do
        expect { post resend_users_sign_in_code_path }.to have_enqueued_mail(SignInCodeMailer, :code)
        expect(response).to redirect_to(users_sign_in_code_path)
        expect(flash[:notice]).to be_nil
      end
    end
  end

  describe "CSRF" do
    around do |ex|
      old = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      ex.run
    ensure
      ActionController::Base.allow_forgery_protection = old
    end

    it "refuses a request without a token" do
      expect { post users_sign_in_codes_path, params: { email: user.email } }.not_to change(SignInCode, :count)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "refuses a verify without a token" do
      ActionController::Base.allow_forgery_protection = false
      request_code(user.email, code: "424242")
      ActionController::Base.allow_forgery_protection = true
      verify("424242")
      expect(SignInCode.sole.consumed_at).to be_nil
      get "/dashboard/apps"
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "Turnstile" do
    before do
      Wokku.configure { |c| c.turnstile_site_key = "site"; c.turnstile_secret_key = "secret" }
    end

    def stub_siteverify(**response)
      stub_request(:post, siteverify).to_return(**response)
    end

    it "sends the code when Cloudflare says success, posting secret, response and remoteip" do
      stub = stub_request(:post, siteverify)
        .with(body: { "secret" => "secret", "response" => "tok", "remoteip" => "127.0.0.1" })
        .to_return(status: 200, body: { success: true }.to_json)
      expect { request_code(user.email, "cf-turnstile-response" => "tok") }.to have_enqueued_mail(SignInCodeMailer, :code)
      expect(stub).to have_been_requested
      expect(response).to redirect_to(users_sign_in_code_path)
    end

    {
      "a failed check" => { status: 200, body: { success: false }.to_json },
      "a non-success response" => { status: 500, body: "oops" },
      "garbage JSON" => { status: 200, body: "[]" }
    }.each do |label, res|
      it "fails closed on #{label}" do
        stub_siteverify(**res)
        expect { request_code(user.email, "cf-turnstile-response" => "tok") }.not_to change(SignInCode, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(CGI.escapeHTML(I18n.t("sign_in_codes.bot_check_failed")))
      end
    end

    it "fails closed on a timeout" do
      stub_request(:post, siteverify).to_timeout
      expect { request_code(user.email, "cf-turnstile-response" => "tok") }.not_to change(SignInCode, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fails closed without calling Cloudflare when the token is missing" do
      request_code(user.email)
      expect(response).to have_http_status(:unprocessable_content)
      expect(a_request(:post, siteverify)).not_to have_been_made
    end

    it "answers an unknown email exactly as a known one when the check fails" do
      stub_siteverify(status: 200, body: { success: false }.to_json)
      request_code("nobody@example.com", "cf-turnstile-response" => "tok")
      unknown = [ response.status, response.body.scan(/role="alert"[^<]*/) ]
      request_code(user.email, "cf-turnstile-response" => "tok")
      expect([ response.status, response.body.scan(/role="alert"[^<]*/) ]).to eq(unknown)
    end

    it "gates resend too" do
      stub_siteverify(status: 200, body: { success: true }.to_json)
      request_code(user.email, "cf-turnstile-response" => "tok")
      stub_siteverify(status: 200, body: { success: false }.to_json)
      travel 46.seconds do
        expect { post resend_users_sign_in_code_path, params: { "cf-turnstile-response" => "tok" } }
          .not_to have_enqueued_mail(SignInCodeMailer, :code)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "does not gate verify" do
      stub_siteverify(status: 200, body: { success: true }.to_json)
      request_code(user.email, code: "424242", "cf-turnstile-response" => "tok")
      WebMock.reset!
      verify("424242")
      expect(response).to redirect_to(root_path)
    end

    it "speaks Indonesian" do
      expect(I18n.t("sign_in_codes.bot_check_failed", locale: :id)).to eq("Kami tidak bisa memastikan kamu manusia. Coba lagi.")
    end
  end
end

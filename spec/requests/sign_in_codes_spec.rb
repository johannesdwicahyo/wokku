# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email sign-in code", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper

  let(:user) { users(:one) }
  before { user.update_columns(email_provider_verified: true) }

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

  # Mails actually delivered by the jobs the block enqueued.
  def mails_sent(&)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs(only: SignInCodeMailer::DeliveryJob, &)
    ActionMailer::Base.deliveries
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
      delete users_sign_in_code_path
      expect(response).to have_http_status(:not_found)
      expect(SignInCode.count).to eq(0)
    end

    it "404s a signed-in user too" do
      Wokku.configure { |c| c.email_sign_in = false }
      sign_in user
      post users_sign_in_codes_path, params: { email: user.email }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "step 1" do
    it "answers the same for an unknown, a suspended and an active email; mails only the active one" do
      suspended = create(:user, abuse_suspended_at: Time.current)
      answers = {}
      { unknown: "nobody-#{SecureRandom.hex(3)}@example.com", suspended: suspended.email }.each do |kind, email|
        Wokku.configure { |c| c.open_registration = false } if kind == :unknown # unknown + closed = no mail
        expect(mails_sent { request_code(email) }).to be_empty
        answers[kind] = [ response.status, response.location, flash[:notice], flash[:alert], session[:sign_in_code_email] == email ]
        Wokku.configure { |c| c.open_registration = true }
      end
      expect(mails_sent { request_code(user.email) }.sole.to).to eq([ user.email ])
      answers[:active] = [ response.status, response.location, flash[:notice], flash[:alert], session[:sign_in_code_email] == user.email ]
      expect(answers[:active].last).to be(true)

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

    it "gives the cooldown notice on a second request within 45 s" do
      freeze_time
      request_code(user.email)
      travel 10.seconds do
        expect { request_code(user.email) }.not_to have_enqueued_mail(SignInCodeMailer, :code)
        expect(response).to redirect_to(users_sign_in_code_path)
        expect(flash[:notice]).to eq(I18n.t("sign_in_codes.cooldown", n: 35))
      end
    end

    it "reads the email from the form body only, not the query string" do
      post "#{users_sign_in_codes_path}?email=#{CGI.escape("other@example.com")}", params: { email: user.email }
      expect(session[:sign_in_code_email]).to eq(user.email)
      expect(SignInCode.pluck(:email)).to eq([ user.email ])
    end

    it "refuses a JSON body with 422, sending nothing" do
      expect { post users_sign_in_codes_path, params: { email: user.email }, as: :json }.not_to change(SignInCode, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(session[:sign_in_code_email]).to be_nil
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

    it "counts the resend down from Issue's real wait, not a flat 45 s" do
      freeze_time
      request_code(user.email)
      expect(session[:sign_in_code_resend_at]).to eq(45.seconds.from_now.to_i)
      2.times { travel 46.seconds; post resend_users_sign_in_code_path }
      travel 46.seconds
      post resend_users_sign_in_code_path # 4th in 10 min: Issue's 3-per-window cooldown
      wait = (10.minutes - 3 * 46.seconds).to_i
      expect(flash[:notice]).to eq(I18n.t("sign_in_codes.cooldown", n: wait))
      travel 2.seconds
      get users_sign_in_code_path
      remaining = Nokogiri::HTML(response.body).at_css("[data-sign-in-code-remaining-value]")["data-sign-in-code-remaining-value"]
      expect(remaining.to_i).to eq(wait - 2)
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
      admin.update_columns(email_provider_verified: true)
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

  describe "planted email (a GitHub user sets their profile email to a future victim's)" do
    it "mails nothing for that email and never signs in, even with a matching code" do
      attacker = create(:user, provider: "github", uid: "gh-attacker", email_provider_verified: true)
      sign_in attacker
      patch "/dashboard/profile", params: { user: { email: "victim@example.com" } }
      expect(attacker.reload).to have_attributes(email: "victim@example.com", email_provider_verified: false)
      sign_out attacker

      expect(mails_sent { request_code("victim@example.com") }).to be_empty
      expect(SignInCode.sole.code_digest).to eq(SignInCode::UNMATCHABLE)

      allow_any_instance_of(SignInCode).to receive(:matches?).and_return(true) # as if the guess were right
      verify("424242")
      expect(response).to have_http_status(:unprocessable_content)
      get "/dashboard/apps"
      expect(response).to redirect_to(new_user_session_path)
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

  describe "resend chain" do
    it "refuses a resend once the human check is over 30 minutes old, and resend never refreshes it" do
      t0 = Time.current
      request_code(user.email)
      human_at = session[:sign_in_code_human_at]
      expect(human_at).to be_present
      [ 9, 18, 27 ].each do |m| # each resend keeps the pending email fresh
        travel_to(t0 + m.minutes) do
          expect { post resend_users_sign_in_code_path }.to have_enqueued_mail(SignInCodeMailer, :code)
          expect(response).to redirect_to(users_sign_in_code_path)
        end
      end
      expect(session[:sign_in_code_human_at]).to eq(human_at)
      travel_to(t0 + 31.minutes) do
        expect { post resend_users_sign_in_code_path }.not_to have_enqueued_mail(SignInCodeMailer, :code)
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to eq(I18n.t("sign_in_codes.start_again"))
        expect(session[:sign_in_code_email]).to be_nil
      end
    end
  end

  describe "use a different email" do
    it "clears every pending key and goes back to sign-in" do
      request_code(user.email)
      delete users_sign_in_code_path
      expect(response).to redirect_to(new_user_session_path)
      expect(session.to_h.keys.grep(/sign_in_code/)).to be_empty
      get users_sign_in_code_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "is a DELETE form on step 2" do
      request_code(user.email)
      get users_sign_in_code_path
      form = Nokogiri::HTML(response.body).css("form[action='#{users_sign_in_code_path}']").find { |f| f.at_css("input[name='_method'][value='delete']") }
      expect(form).to be_present
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

    it "does not gate resend (the create check bounds it)" do
      stub_siteverify(status: 200, body: { success: true }.to_json)
      request_code(user.email, "cf-turnstile-response" => "tok")
      WebMock.reset!
      travel 46.seconds do
        expect { post resend_users_sign_in_code_path }.to have_enqueued_mail(SignInCodeMailer, :code)
        expect(response).to redirect_to(users_sign_in_code_path)
      end
    end

    it "accepts a matching hostname and fails closed on another one" do
      stub_siteverify(status: 200, body: { success: true, hostname: "www.example.com" }.to_json)
      request_code(user.email, "cf-turnstile-response" => "tok")
      expect(response).to redirect_to(users_sign_in_code_path)
      stub_siteverify(status: 200, body: { success: true, hostname: "evil.test" }.to_json)
      travel 46.seconds do
        expect { request_code(user.email, "cf-turnstile-response" => "tok") }.not_to change(SignInCode, :count)
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

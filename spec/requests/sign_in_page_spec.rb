# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sign-in page", type: :request do
  let(:all_providers_env) do
    { "GITHUB_OAUTH_CLIENT_ID" => "x", "GOOGLE_OAUTH_CLIENT_ID" => "x", "GITLAB_OAUTH_CLIENT_ID" => "x",
      "BITBUCKET_OAUTH_CLIENT_ID" => "x", "APPLE_SERVICES_ID" => "cloud.wokku.signin", "APPLE_TEAM_ID" => "T",
      "APPLE_KEY_ID" => "K", "APPLE_PRIVATE_KEY" => "pem" }
  end
  let(:no_providers_env) { ENV.to_h.except(*all_providers_env.keys) }

  def html = Nokogiri::HTML(response.body)

  def provider_forms
    html.css("form[action^='/users/auth/']")
  end

  context "with every provider configured" do
    before do
      stub_const("ENV", ENV.to_h.merge(all_providers_env))
      get new_user_session_path
    end

    it "lists providers GitHub first and wide, in the fixed order, each tracked" do
      expect(response).to have_http_status(:ok)
      actions = provider_forms.map { |f| f["action"] }
      expect(actions).to eq(%w[github google_oauth2 apple gitlab bitbucket].map { |p| "/users/auth/#{p}" })
      expect(provider_forms.first["class"]).to include("col-span-2")
      expect(provider_forms[1..].map { |f| f["class"].to_s }).to all(satisfy { |c| !c.include?("col-span-2") })

      props = provider_forms.map do |f|
        btn = f.at_css("button")
        expect(btn["data-track-event-value"]).to eq("signup_started")
        expect(btn["data-turbo"]).to eq("false")
        JSON.parse(btn["data-track-props-value"])["provider"]
      end
      expect(props).to eq(%w[github google apple gitlab bitbucket])
    end

    it "gives every provider button a 'Continue with X' accessible name" do
      names = provider_forms.map { |f| f.at_css("button")["aria-label"] }
      expect(names).to eq([ "Continue with GitHub", "Continue with Google", "Continue with Apple",
                            "Continue with GitLab", "Continue with Bitbucket" ])
      expect(provider_forms.first.at_css("button").text.squish).to eq("Continue with GitHub")
      expect(provider_forms[1].at_css("button").text.squish).to eq("Google")
    end

    it "shows no password field, shows the reassurance" do
      expect(response.body).not_to include("user[password]")
      expect(response.body).to include("repos or code")
    end
  end

  context "with no providers" do
    before do
      stub_const("ENV", no_providers_env)
      get new_user_session_path
    end

    it "renders the email and password fields in form#signin-form and no provider buttons" do
      form = html.at_css("form#signin-form")
      expect(form).to be_present
      expect(form.at_css("input[type=email][name='user[email]']")).to be_present
      expect(form.at_css("input[type=password][name='user[password]']")).to be_present
      expect(provider_forms).to be_empty
      expect(response.body).not_to include("repos or code")
    end
  end

  describe "the shell" do
    before do
      stub_const("ENV", no_providers_env.merge("WOKKU_REGION" => "JKT-01"))
      get new_user_session_path
    end

    it "renders the title, the language switch and a decorative aside with the sign-in wall" do
      expect(html.at_css("h1").text).to eq("Sign in to Wokku")
      expect(response.body).to include("Your apps are waiting.")
      expect(html.at_css("a[aria-label][href='/']")).to be_present
      expect(html.css("form[action^='/locale']").size).to eq(2)

      aside = html.at_css("aside")
      expect(aside["aria-hidden"]).to eq("true")
      expect(aside["class"]).to include("hidden", "min-[960px]:block")
      canvas = aside.at_css("canvas[data-controller='light-wall']")
      expect(canvas["data-light-wall-logo-value"]).to eq("true")
      expect(canvas["data-light-wall-pulse-form-value"]).to eq("signin-form")
      expect(aside.at_css("[data-controller='clock'][data-clock-zone-value='Asia/Jakarta']")).to be_present
      expect(aside.text).to include("JKT-01", "Push your code.", "git push wokku main")
    end

    it "uses footer.legal and makes no speed claims or company-name claims" do
      expect(response.body).to include("© 2026 Wokku · wokku.cloud")
      [ "~60", "minute", "menit", "PT Wokku", "no card" ].each { |s| expect(response.body).not_to include(s) }
    end
  end

  it "says signing in creates an account on the cloud only" do
    stub_const("ENV", no_providers_env)
    get new_user_session_path
    expect(response.body).not_to include("Signing in creates your free account")
    allow(Wokku).to receive(:cloud?).and_return(true)
    get new_user_session_path
    expect(response.body).to include("Signing in creates your free account. No card needed.")
  end

  describe "in Indonesian" do
    let(:en) { I18n.t("signin", locale: :en).stringify_keys }

    it "has no English sign-in strings" do
      stub_const("ENV", ENV.to_h.merge(all_providers_env))
      allow(Wokku).to receive(:cloud?).and_return(true)
      get new_user_session_path(locale: "id")
      expect(html.at_css("h1").text).to eq("Masuk ke Wokku")
      %w[title sub quote new_account reassure].each { |k| expect(response.body).not_to include(en[k]) }
      expect(response.body).not_to include("Continue with")
      expect(response.body).not_to include("By signing in")
    end

    it "shows Devise's failure message in Indonesian" do
      stub_const("ENV", no_providers_env)
      user = create(:user, :with_personal_team)
      post user_session_path(locale: "id"), params: { user: { email: user.email, password: "wrong-password" } }
      expect(response.body).to include(I18n.t("devise.failure.invalid", locale: :id, authentication_keys: "Email"))
      expect(I18n.t("devise.failure.invalid", locale: :id)).not_to include("Invalid")
    end
  end

  describe "2FA via password" do
    let(:user) do
      create(:user, :with_personal_team, otp_secret: User.generate_otp_secret, otp_required_for_login: true)
    end

    before { stub_const("ENV", no_providers_env) }

    it "lands on the challenge in the shell, signs in with the right code, re-renders on a wrong one" do
      post user_session_path, params: { user: { email: user.email, password: "supersecret123" } }
      expect(response).to redirect_to(users_two_factor_path)
      get users_two_factor_path
      expect(html.at_css("aside[aria-hidden='true'] canvas[data-controller='light-wall']")).to be_present
      expect(html.at_css("form#signin-form input[name=code][autocomplete='one-time-code']")).to be_present

      post users_two_factor_path, params: { code: "abcdef" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("auth.two_factor_challenge.invalid"))
      expect(html.at_css("aside[aria-hidden='true']")).to be_present

      post users_two_factor_path, params: { code: user.current_otp }
      expect(response).to have_http_status(:redirect)
      get "/dashboard/apps"
      expect(response).to have_http_status(:ok)
    end
  end
end

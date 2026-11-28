# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email sign-in code UI", type: :request do
  let(:providers_env) { { "GITHUB_OAUTH_CLIENT_ID" => "x" } }
  let(:no_providers_env) { ENV.to_h.except("GITHUB_OAUTH_CLIENT_ID", "GOOGLE_OAUTH_CLIENT_ID", "GITLAB_OAUTH_CLIENT_ID", "BITBUCKET_OAUTH_CLIENT_ID", "APPLE_SERVICES_ID") }
  let(:turnstile_src) { "https://challenges.cloudflare.com/turnstile/v0/api.js" }

  def html = Nokogiri::HTML(response.body)

  around do |ex|
    ex.run
  ensure
    Wokku.configure { |c| c.email_sign_in = nil; c.turnstile_site_key = nil; c.turnstile_secret_key = nil }
  end

  context "flag on with providers" do
    before do
      Wokku.configure { |c| c.email_sign_in = true }
      stub_const("ENV", ENV.to_h.merge(providers_env))
      get new_user_session_path
    end

    it "shows the divider and the email form, no password form, no Turnstile" do
      expect(response.body).to include("or with your email")
      form = html.at_css("form#signin-form")
      expect(form["action"]).to eq("/users/sign_in/code")
      input = form.at_css("input[type=email]")
      expect(input.attributes.keys).to include("required")
      expect(input["autocomplete"]).to eq("email")
      expect(form.text).to include("Email me a sign-in code")
      expect(response.body).not_to include("user[password]")
      expect(response.body).not_to include("turnstile")
      expect(html.at_css("canvas")["data-light-wall-pulse-form-value"]).to eq("signin-form")
    end
  end

  context "flag on, no providers" do
    it "has no divider, still the email form and no password form" do
      Wokku.configure { |c| c.email_sign_in = true }
      stub_const("ENV", no_providers_env)
      get new_user_session_path
      expect(response.body).not_to include("or with your email")
      expect(html.at_css("form#signin-form input[type=email]")).to be_present
      expect(response.body).not_to include("user[password]")
    end
  end

  context "flag off" do
    it "keeps the Phase 8 password form" do
      stub_const("ENV", no_providers_env)
      get new_user_session_path
      expect(response.body).to include("user[password]")
      expect(response.body).not_to include("or with your email")
    end
  end

  context "Turnstile" do
    before { Wokku.configure { |c| c.email_sign_in = true } }

    it "renders the widget and script only when the site key is set" do
      Wokku.configure { |c| c.turnstile_site_key = "site-key-1" }
      get new_user_session_path
      widget = html.at_css("form#signin-form .cf-turnstile")
      expect(widget["data-sitekey"]).to eq("site-key-1")
      expect(widget["data-language"]).to eq("en")
      script = html.at_css("script[src='#{turnstile_src}']")
      expect(script.attributes.keys).to include("async", "defer")
    end
  end

  context "step 1 error re-render" do
    it "prefills the email and shows the error inline" do
      Wokku.configure { |c| c.email_sign_in = true }
      post users_sign_in_codes_path, params: { email: "not-an-email" }
      expect(response).to have_http_status(:unprocessable_content)
      input = html.at_css("input[type=email]")
      expect(input["value"]).to eq("not-an-email")
      err = html.at_css("##{input['aria-describedby']}")
      expect(err["role"]).to eq("alert")
      expect(err.text).to include("valid email")
    end
  end

  context "step 2" do
    before do
      Wokku.configure { |c| c.email_sign_in = true }
      post users_sign_in_codes_path, params: { email: "step2@example.com" }
    end

    it "renders the sent copy, the one-time-code input and the shell pulse form" do
      get users_sign_in_code_path
      expect(html.at_css("p b").text).to eq("step2@example.com")
      expect(html.text).to include("It works once, for 10 minutes")
      input = html.at_css("form#signin-form input[name=code]")
      expect(input["inputmode"]).to eq("numeric")
      expect(input["autocomplete"]).to eq("one-time-code")
      expect(input["maxlength"]).to eq("6")
      expect(input["pattern"]).to eq("[0-9]{6}")
      expect(input.attributes.keys).to include("required")
      expect(html.at_css("canvas")["data-light-wall-pulse-form-value"]).to eq("signin-form")
      expect(html.at_css("form[action='/users/sign_in/code'] input[name=_method][value=delete]")).to be_present
      expect(html.at_css("[data-controller=sign-in-code]")["data-sign-in-code-remaining-value"].to_i).to be_between(1, 45)
      expect(html.at_css("form[action='/users/sign_in/code/resend']")).to be_present
    end

    it "shows a wrong-code error inline" do
      post verify_users_sign_in_code_path, params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      err = html.at_css("#code-error")
      expect(err["role"]).to eq("alert")
      expect(html.at_css("input[name=code]")["aria-describedby"]).to eq("code-error")
    end

    it "has no English in id" do
      get users_sign_in_code_path, params: { locale: "id" }
      follow_redirect! if response.redirect?
      body = html.text
      expect(body).to include("Kami mengirim kode 6 digit ke")
      expect(body).to include("Pakai email lain")
      expect(body).not_to match(/We sent|Use a different|Send a new|Sign in\b/)
    end
  end

  it "never nests a form, and verify has no _method" do
    Wokku.configure { |c| c.email_sign_in = true }
    pages = [ -> { get new_user_session_path } ]
    pages.each(&:call)
    doc = Nokogiri::HTML5(response.body)
    expect(doc.css("form form")).to be_empty
    post users_sign_in_codes_path, params: { email: "nest@example.com" }
    get users_sign_in_code_path
    doc = Nokogiri::HTML5(response.body)
    expect(doc.css("form form")).to be_empty
    expect(doc.at_css("form#signin-form input[name=_method]")).to be_nil
    expect(doc.at_css("label[for=code]")).to be_present
    expect(doc.at_css("form#signin-form input#code")).to be_present
  end

  it "keeps non-code alerts top-level, not on the email field" do
    Wokku.configure { |c| c.email_sign_in = true }
    get "/dashboard/apps"
    follow_redirect! while response.redirect?
    expect(html.at_css("[role=alert]")).to be_present
    expect(html.at_css("input[type=email]")["aria-invalid"]).not_to eq("true")
  end

  it "does not mark the code field invalid for the cooldown notice" do
    Wokku.configure { |c| c.email_sign_in = true }
    post users_sign_in_codes_path, params: { email: "cool@example.com" }
    post resend_users_sign_in_code_path
    follow_redirect!
    expect(response.body).to include("Wait")
    expect(html.at_css("input[name=code]")["aria-invalid"]).not_to eq("true")
    expect(html.at_css("#code-error")).to be_nil
  end

  it "has no English on step 1 in id" do
    Wokku.configure { |c| c.email_sign_in = true }
    get new_user_session_path, params: { locale: "id" }
    expect(html.text).to include("Kirim kode masuk ke email")
    expect(html.at_css("form#signin-form").text).not_to include("Email me")
  end
end

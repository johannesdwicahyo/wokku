require "rails_helper"

RSpec.describe "LocalesController", type: :request do
  include Devise::Test::IntegrationHelpers

  it "sets a cookie for a supported locale" do
    post "/locale", params: { locale: "id" }
    expect(response).to be_redirect
    expect(cookies[:locale]).to eq("id")
  end

  it "ignores an unsupported locale" do
    post "/locale", params: { locale: "fr" }
    expect(response).to be_redirect
    expect(cookies[:locale]).to be_nil
  end

  it "updates a signed-in user's locale without touching currency" do
    user = users(:one)
    user.update!(currency: "usd")
    sign_in user

    post "/locale", params: { locale: "id" }
    expect(response).to be_redirect
    expect(user.reload.locale).to eq("id")
    expect(user.currency).to eq("usd")
  end

  it "redirects without raising when not signed in" do
    post "/locale", params: { locale: "id" }
    expect(response).to be_redirect
  end

  it "drops ?locale= from the referer but keeps other params" do
    post "/locale", params: { locale: "en" }, headers: { "Referer" => "http://www.example.com/?locale=id&utm_source=x" }
    expect(response).to redirect_to("/?utm_source=x")
    expect(cookies[:locale]).to eq("en")
  end

  # Docs pages pin their language with ?lang=, which beats the cookie, so the
  # docs top bar's EN/ID switch would do nothing if it were kept.
  it "drops the docs ?lang= too" do
    post "/locale", params: { locale: "id" }, headers: { "Referer" => "http://www.example.com/docs/cli/install?lang=en" }
    expect(response).to redirect_to("/docs/cli/install")
  end

  it "ignores a cross-host referer" do
    post "/locale", params: { locale: "en" }, headers: { "Referer" => "https://evil.example/?a=1" }
    expect(response).to redirect_to("/")
  end

  it "collapses leading slashes in the referer path instead of raising" do
    post "/locale", params: { locale: "en" }, headers: { "Referer" => "http://www.example.com//evil.com/x" }
    expect(response).to redirect_to("/evil.com/x")
  end
end

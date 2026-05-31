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
end

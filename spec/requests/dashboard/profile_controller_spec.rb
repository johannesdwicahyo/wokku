# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Profile", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when not authenticated" do
    get "/dashboard/profile"
    expect(response).to have_http_status(:redirect)
  end

  it "shows profile when authenticated" do
    sign_in user
    get "/dashboard/profile"
    expect(response).to have_http_status(:success)
  end

  it "clears email_provider_verified when the email is edited" do
    user.update_columns(email_provider_verified: true)
    sign_in user
    patch "/dashboard/profile", params: { user: { email: "edited-#{SecureRandom.hex(3)}@example.com" } }
    expect(user.reload.email_provider_verified).to be(false)
  end

  describe "changing the email while email sign-in is on" do
    after { Wokku.configure { |c| c.email_sign_in = nil } }

    it "refuses it for a provider-blank user, with a localized message" do
      Wokku.configure { |c| c.email_sign_in = true }
      sign_in user
      old = user.email
      patch "/dashboard/profile", params: { user: { email: "new-#{SecureRandom.hex(3)}@example.com", locale: "id" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("dashboard.profile.email_change_support", locale: :en)))
      expect(user.reload.email).to eq(old)
      expect(I18n.t("dashboard.profile.email_change_support", locale: :id)).to eq("Untuk mengganti email masuk, hubungi support.")
    end

    it "still saves the other fields when the email is unchanged" do
      Wokku.configure { |c| c.email_sign_in = true }
      sign_in user
      patch "/dashboard/profile", params: { user: { email: user.email, locale: "id" } }
      expect(response).to redirect_to("/dashboard/profile")
      expect(user.reload.locale).to eq("id")
    end

    it "allows it for a user with a provider" do
      Wokku.configure { |c| c.email_sign_in = true }
      user.update_columns(provider: "github", uid: "gh-2")
      sign_in user
      patch "/dashboard/profile", params: { user: { email: "gh-new@example.com" } }
      expect(user.reload.email).to eq("gh-new@example.com")
    end

    it "allows it for a provider-blank user with the flag off" do
      sign_in user
      patch "/dashboard/profile", params: { user: { email: "off-new@example.com" } }
      expect(user.reload.email).to eq("off-new@example.com")
    end
  end
end

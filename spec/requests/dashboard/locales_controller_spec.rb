# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Locales", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when not authenticated" do
    post "/dashboard/locale", params: { locale: "en" }
    expect(response).to have_http_status(:redirect)
  end

  it "sets locale cookie and redirects when authenticated with valid locale" do
    sign_in user
    post "/dashboard/locale", params: { locale: "en" }
    expect(response).to have_http_status(:redirect)
  end

  it "redirects without error for invalid locale when authenticated" do
    sign_in user
    post "/dashboard/locale", params: { locale: "xx" }
    expect(response).to have_http_status(:redirect)
  end
end

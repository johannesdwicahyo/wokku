# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dark-only dashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in users(:one) }

  it "renders color-scheme: dark with no data-theme or toggle" do
    get "/dashboard/apps"
    expect(response.body).to include('style="color-scheme: dark"')
    expect(response.body).not_to include("data-theme")
    expect(response.body).not_to include("theme#toggle")
  end

  it "ignores a saved light theme cookie" do
    cookies[:theme] = "light"
    get "/dashboard/apps"
    expect(response.body).to include("color-scheme: dark")
    expect(response.body).not_to include("data-theme")
  end
end

# frozen_string_literal: true

require "rails_helper"

# The "free Jakarta server" kicker narrates the CLOUD free tier; a self-host
# install (no billing host, like this harness) must not promise it.
RSpec.describe "First-deploy chooser copy", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in create(:user) }

  it "self-host says the app goes live on the operator's own server" do
    get "/dashboard/apps"
    expect(response.body).to include(CGI.escapeHTML(I18n.t("onboarding2.sub_self_host")))
    expect(response.body).not_to include("Jakarta")
  end
end

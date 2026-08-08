# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Scaling", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    allow(Lifecycle::Ops).to receive(:converge!)
  end

  it "redirects to login when not authenticated on show" do
    get "/dashboard/apps/#{app_record.id}/scaling"
    expect(response).to have_http_status(:redirect)
  end

  it "scaling page redirects to merged Resources tab" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/scaling"
    expect(response).to redirect_to(dashboard_app_resources_path(app_record))
  end

  it "updates process scaling and redirects" do
    sign_in user
    patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 1 } }
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/scaling")
    expect(flash[:notice]).to match("Scaling updated")
  end

  it "redirects with alert when converge raises an unexpected error" do
    sign_in user
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(RuntimeError, "converge error")

    patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/scaling")
    expect(flash[:alert]).to match("Scaling failed")
  end
end

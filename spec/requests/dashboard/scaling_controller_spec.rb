# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Scaling", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    allow(Dokku::Client).to receive(:new).and_return(double("Dokku::Client").as_null_object)
    fake_processes = double("Dokku::Processes", scale: nil, list: {})
    allow(Dokku::Processes).to receive(:new).and_return(fake_processes)
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

  it "redirects with alert when Dokku scale raises an unexpected error" do
    sign_in user
    bad_processes = double("Dokku::Processes")
    allow(bad_processes).to receive(:scale).and_raise(RuntimeError, "SSH error")
    allow(bad_processes).to receive(:list).and_return({})
    allow(Dokku::Processes).to receive(:new).and_return(bad_processes)

    patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/scaling")
    expect(flash[:alert]).to match("Scaling failed")
  end
end

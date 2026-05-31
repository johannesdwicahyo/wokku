# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::LogDrains", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)      { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:log_drain) { log_drains(:two) }

  before do
    fake_log_drains = double("Dokku::LogDrains", add: nil, remove: nil)
    allow(Dokku::Client).to receive(:new).and_return(double("Dokku::Client"))
    allow(Dokku::LogDrains).to receive(:new).and_return(fake_log_drains)
  end

  it "redirects to login when not authenticated on create" do
    post "/dashboard/apps/#{app_record.id}/log_drains",
         params: { log_drain: { url: "syslog://logs.example.com:514", drain_type: "syslog" } }
    expect(response).to have_http_status(:redirect)
  end

  it "creates log drain and redirects to logs page" do
    sign_in user
    expect {
      post "/dashboard/apps/#{app_record.id}/log_drains",
           params: { log_drain: { url: "syslog://new.example.com:514", drain_type: "syslog" } }
    }.to change { app_record.log_drains.count }.by(1)
    expect(response).to redirect_to(dashboard_app_log_drains_path(app_record))
  end

  it "redirects with alert on invalid url" do
    sign_in user
    expect {
      post "/dashboard/apps/#{app_record.id}/log_drains",
           params: { log_drain: { url: "not-a-url", drain_type: "syslog" } }
    }.not_to change { app_record.log_drains.count }
    expect(response).to redirect_to(dashboard_app_log_drains_path(app_record))
    expect(flash[:alert]).to match(/URL/)
  end

  it "destroys log drain and redirects" do
    sign_in user
    # Force lazy load before the deletion happens
    ld = log_drain
    expect {
      delete "/dashboard/apps/#{app_record.id}/log_drains/#{ld.id}"
    }.to change { app_record.log_drains.count }.by(-1)
    expect(response).to redirect_to(dashboard_app_log_drains_path(app_record))
  end
end

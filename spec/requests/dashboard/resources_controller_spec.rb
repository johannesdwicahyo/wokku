# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Resources", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    # These examples only assert the HTTP redirect/200, so stub the SSH
    # transport to success rather than wait ~5-10s/example on a real
    # connection timeout.
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return("")
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming).and_return("")
  end

  it "show redirects to login when not authenticated" do
    get "/dashboard/apps/#{app_record.id}/resources"
    expect(response).to have_http_status(:redirect)
  end

  it "show returns 200 for authenticated admin" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/resources"
    expect(response).to have_http_status(:success)
  end

  it "create redirects when not authenticated" do
    post "/dashboard/apps/#{app_record.id}/resources",
         params: { service_type: "postgres", addon_name: "test-pg" }
    expect(response).to have_http_status(:redirect)
  end

  it "create rescues a provisioner error and redirects" do
    sign_in user
    # Raise directly: letting the real provisioner run makes this example
    # poll the typed-ops loop to its multi-minute timeout before rescuing.
    allow(DatabaseProvisioner).to receive(:new).and_raise(StandardError, "host down")
    post "/dashboard/apps/#{app_record.id}/resources",
         params: { service_type: "postgres", addon_name: "test-pg" }
    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/Failed to add postgres/)
  end

  it "destroy redirects when not authenticated" do
    db = database_services(:two)
    delete "/dashboard/apps/#{app_record.id}/resources", params: { addon_id: db.id }
    expect(response).to have_http_status(:redirect)
  end

  it "destroy rescues a destroy error and redirects" do
    sign_in user
    db = database_services(:two)
    allow(DatabaseProvisioner).to receive(:destroy!).and_raise(StandardError, "op failed")
    delete "/dashboard/apps/#{app_record.id}/resources", params: { addon_id: db.id }
    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/Failed to remove add-on/)
  end

  describe "success paths and scale sync" do
    before { sign_in user }

    it "create succeeds, tracks and redirects with the dedicated label" do
      provisioner = double(call: database_services(:two))
      allow(DatabaseProvisioner).to receive(:new).and_return(provisioner)
      post "/dashboard/apps/#{app_record.id}/resources",
           params: { service_type: "postgres", addon_name: "ok-pg" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/resources")
      expect(flash[:notice]).to match(/added and linked/)
    end

    it "show syncs process scales from live heartbeat containers" do
      app_record.update!(live_containers: [
        { "process" => "cron" }, { "process" => "cron" }, { "bogus" => true }
      ])
      get "/dashboard/apps/#{app_record.id}/resources", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
      # "cron" has no fixture ProcessScale, so the sync creates it fresh.
      expect(app_record.process_scales.find_by(process_type: "cron")&.count).to eq(2)
    end

    it "show survives a scale-sync failure" do
      allow_any_instance_of(AppRecord).to receive(:live_containers).and_raise(StandardError, "bad json")
      get "/dashboard/apps/#{app_record.id}/resources", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
    end
  end
end

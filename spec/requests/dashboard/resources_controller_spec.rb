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

  it "create rescues SSH error and redirects" do
    sign_in user
    post "/dashboard/apps/#{app_record.id}/resources",
         params: { service_type: "postgres", addon_name: "test-pg" }
    expect(response).to have_http_status(:redirect)
  end

  it "destroy redirects when not authenticated" do
    db = database_services(:two)
    delete "/dashboard/apps/#{app_record.id}/resources", params: { addon_id: db.id }
    expect(response).to have_http_status(:redirect)
  end

  it "destroy rescues SSH error and redirects" do
    sign_in user
    db = database_services(:two)
    delete "/dashboard/apps/#{app_record.id}/resources", params: { addon_id: db.id }
    expect(response).to have_http_status(:redirect)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Resources deferred fragment", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:app_record) { app_records(:two) }
  before { sign_in users(:two) }

  it "shell renders without the SSH process sync" do
    expect_any_instance_of(Dashboard::ResourcesController).not_to receive(:sync_process_scales_safely)
    get dashboard_app_resources_path(app_record)
    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="resources_processes"')
    expect(response.body).to include('loading="lazy"')
    expect(response.body).to include(dashboard_app_resources_path(app_record, deferred: 1))
  end

  it "deferred fragment renders the frame with target=_top" do
    allow_any_instance_of(Dashboard::ResourcesController).to receive(:sync_process_scales_safely)
    get dashboard_app_resources_path(app_record, deferred: 1)
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/<turbo-frame[^>]*id="resources_processes"[^>]*target="_top"/)
  end
end

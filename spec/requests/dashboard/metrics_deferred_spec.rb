# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Metrics deferred fragment", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:app_record) { app_records(:two) }
  before { sign_in users(:two) }

  it "shell renders instantly without SSH and shows the deferred placeholder" do
    # Shell must NOT call the SSH fetchers.
    expect_any_instance_of(Dashboard::MetricsController).not_to receive(:fetch_container_stats)
    get dashboard_app_metrics_path(app_record)
    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="metrics_live"')
    expect(response.body).to include('loading="lazy"')
    expect(response.body).to include(dashboard_app_metrics_path(app_record, deferred: 1))
  end

  it "deferred fragment renders the metrics_live frame with target=_top" do
    allow_any_instance_of(Dashboard::MetricsController).to receive(:fetch_container_stats).and_return([])
    allow_any_instance_of(Dashboard::MetricsController).to receive(:fetch_processes).and_return([])
    get dashboard_app_metrics_path(app_record, deferred: 1)
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/<turbo-frame[^>]*id="metrics_live"[^>]*target="_top"/)
  end
end

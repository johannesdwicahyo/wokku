# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Performance tab IA", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  before { sign_in user }

  it "renders metrics with the Performance sub-nav (lands on metrics)" do
    get dashboard_app_metrics_path(app_record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dashboard_app_monitor_path(app_record))      # Requests link present
    expect(response.body).to include(dashboard_app_performance_path(app_record))  # Vitals link present
  end

  it "renders the requests (monitor) page under Performance" do
    get dashboard_app_monitor_path(app_record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dashboard_app_metrics_path(app_record))
  end

  it "renders the vitals page with the Performance sub-nav" do
    get dashboard_app_performance_path(app_record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dashboard_app_metrics_path(app_record))
  end

  it "Performance top-tab points at the metrics (basic) page" do
    get dashboard_app_path(app_record)
    expect(response.body).to include(dashboard_app_metrics_path(app_record))
  end
end

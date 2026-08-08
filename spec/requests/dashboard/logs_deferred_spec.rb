# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Logs deferred fragment", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:app_record) { app_records(:two) }
  before { sign_in users(:two) }

  it "shell renders without SSH log fetch" do
    expect_any_instance_of(Dashboard::LogsController).not_to receive(:fetch_recent_logs)
    get dashboard_app_logs_path(app_record)
    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="logs_stream"')
    expect(response.body).to include('loading="lazy"')
  end

  it "deferred fragment renders the logs_stream frame with target=_top" do
    allow_any_instance_of(Dashboard::LogsController).to receive(:fetch_recent_logs).and_return([])
    get dashboard_app_logs_path(app_record, deferred: 1)
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/<turbo-frame[^>]*id="logs_stream"[^>]*target="_top"/)
  end

  # Regression: the deferred src must carry the shell's filter state, or the
  # lazy fetch ignores the user's search/level/line-count selections.
  it "forwards search + level + lines filters into the deferred src" do
    get dashboard_app_logs_path(app_record, q: "boom", level: "error", lines: "100")
    expect(response).to have_http_status(:success)
    src = response.body[/src="([^"]*sections?[^"]*|[^"]*deferred=1[^"]*)"/, 1] ||
          response.body[/<turbo-frame[^>]*id="logs_stream"[^>]*src="([^"]*)"/, 1]
    expect(src).to include("deferred=1")
    expect(src).to include("q=boom")
    expect(src).to include("level=error")
    expect(src).to include("lines=100")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Checks deferred fragment", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:app_record) { app_records(:two) }
  before { sign_in users(:two) }

  it "shell renders without SSH" do
    expect(Hosts::Ssh).not_to receive(:new)
    get dashboard_app_checks_path(app_record)
    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="checks_report"')
    expect(response.body).to include('loading="lazy"')
    expect(response.body).to include(dashboard_app_checks_path(app_record, deferred: 1))
  end

  it "deferred fragment renders the frame with target=_top — no SSH, Swarm-supervised notice" do
    expect(Hosts::Ssh).not_to receive(:new)
    get dashboard_app_checks_path(app_record, deferred: 1)
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/<turbo-frame[^>]*id="checks_report"[^>]*target="_top"/)
    expect(response.body).to include("Swarm runtime")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Apps box-size auto-upgrade", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:team_plan) do
    p = Plan.find_or_initialize_by(key: "team")
    p.assign_attributes(name: "Team", price_usd_cents: 5000, price_idr: 750_000,
                        seats_included: 3, box_quotas: { "large" => 3, "sleeping" => 3 })
    p.save!(validate: false)
    p
  end
  let(:user)   { create(:user, plan: team_plan) }
  let(:team)   { create(:team, owner: user, kind: :personal) }
  let(:server) { create(:server, team: team) }

  before do
    create(:team_membership, team: team, user: user, role: :admin)
    # Quotas come from the injected enforcer (OSS default is unlimited, so
    # nothing would ever auto-upgrade). Stub a Team-shaped grant — large-only —
    # so resolve_box_size's upgrade walk is what this spec exercises.
    allow(Wokku.config.plan_enforcer).to receive(:quota) do |_user, _kind, size|
      team_plan.box_quotas.fetch(size.to_s, 0)
    end
    sign_in user
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  it "upgrades a small box request to large for a Team user" do
    post "/dashboard/apps", params: {
      app_record: { name: "manual-app", server_id: server.id, box_size: "small" }
    }
    app = AppRecord.find_by(name: "manual-app")
    expect(app).to be_present
    expect(app.box_size).to eq("large")
  end
end

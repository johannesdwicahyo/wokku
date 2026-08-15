# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Templates auto-upgrade", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  # A template whose min_tier is "basic" (→ small box). brightbean-studio
  # ships with min_tier basic + a postgres addon.
  let(:small_template) do
    TemplateRegistry.new.all.find { |t| t[:min_tier].to_s == "basic" }
  end

  let(:team_plan) do
    p = Plan.find_or_initialize_by(key: "team")
    p.assign_attributes(name: "Team", price_usd_cents: 5000, price_idr: 750_000,
                        seats_included: 3, box_quotas: { "large" => 3, "sleeping" => 3 })
    p.save!(validate: false)
    p
  end
  # A team-admin (TeamMembership role :admin) member user — NOT the platform
  # admin role (User#role :admin is restricted to a single fixed email and
  # would trip enforce_admin_2fa!). Team admin is what the quota path needs.
  let(:user)   { create(:user, plan: team_plan) }
  let(:team)   { create(:team, owner: user, kind: :personal) }
  let(:server) { create(:server, team: team) }

  before do
    create(:team_membership, team: team, user: user, role: :admin)
    # The global `performance` dyno_tier fixture (size→large) already exists
    # (config.global_fixtures = :all); do NOT create one — name is unique.
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
    # Quotas come from the injected enforcer (OSS default is unlimited, so
    # nothing would ever auto-upgrade). Stub a Team-shaped grant — large-only —
    # so resolve_box_size's upgrade walk is what this spec exercises.
    allow(Wokku.config.plan_enforcer).to receive(:quota) do |_user, _kind, size|
      team_plan.box_quotas.fetch(size.to_s, 0)
    end
    sign_in user
  end

  it "deploys a small-min template on a large box for a Team user" do
    skip "no basic-tier template registered" unless small_template

    expect {
      post "/dashboard/templates",
           params: { template_slug: small_template[:slug], app_name: "bb-test", server_id: server.id }
    }.to change(AppRecord, :count).by(1)

    app = AppRecord.find_by(name: "bb-test")
    expect(app.box_size).to eq("large")
    expect(response).to have_http_status(:redirect)
  end
end

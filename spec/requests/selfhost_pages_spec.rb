# frozen_string_literal: true

require "rails_helper"

# Self-host (no billing host — this harness) regressions from the
# 2026-11-16 install audit: pages that 500'd on cloud-only billing code,
# a workspace form that demanded a paid plan nobody can buy, and
# wokku.cloud-only copy shown to self-hosters.
RSpec.describe "Self-host dashboard pages", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  it "renders the profile edit page (was a 500 on resource_usages)" do
    get "/dashboard/profile/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Billing currency")
  end

  it "redirects the plan/invoice usage page instead of a 500" do
    get "/dashboard/usage"
    expect(response).to redirect_to("/dashboard/apps")
  end

  it "renders an incoming app transfer without cloud price helpers (was a 500)" do
    transfer = AppTransfer.create!(app_record: app_records(:one), from_user: users(:one), to_user: users(:two))
    sign_in users(:two)
    get "/dashboard/app_transfers/#{transfer.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Estimated Monthly Cost", "Billing will start")
  end

  it "creates a workspace without a paid plan" do
    expect {
      post "/dashboard/workspaces", params: { team: { name: "Selfhost Org #{SecureRandom.hex(3)}" } }
    }.to change { user.teams.count }.by(1)
    expect(user.teams.order(:created_at).last.plan.key).to eq("free")
  end

  it "does not show paid-plan copy on the workspaces page" do
    get "/dashboard/workspaces"
    expect(response.body).not_to include("require a paid plan")
    expect(response.body).not_to match(/Rp[\d.]+\/mo/)
  end

  it "shows no wokku.cloud support inbox, billing currency, or API host" do
    get "/dashboard/profile"
    expect(response.body).not_to include("support@wokku.cloud", "Billing currency", "https://wokku.cloud/api")
    expect(response.body).to include("http://www.example.com/api/v1")
  end
end

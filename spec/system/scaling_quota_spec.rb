require "rails_helper"

# Named :system per the plan but runs as a request spec (rack_test, no JS)
# to exercise the full controller stack including rescue_from + flash redirect.
RSpec.describe "Scaling under plan quota", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:solo_plan) { Plan.find_by(key: "solo") || Plan.find_or_create_by!(key: "solo") { |p| p.name = "Solo"; p.price_usd_cents = 500; p.price_idr = 0; p.seats_included = 1; p.box_quotas = { "small" => 3, "sleeping" => 3 } } }
  let(:tier)      { create(:dyno_tier, size_key: "small", memory_mb: 512) }
  let(:user)      { create(:user, plan: solo_plan) }
  let(:the_team) do
    t = create(:team, owner: user)
    create(:team_membership, team: t, user: user, role: :admin)
    t
  end
  let(:the_app) { create(:app_record, team: the_team) }

  it "blocks scaling above Solo's small quota with a clear message" do
    create(:dyno_allocation, app_record: the_app, process_type: "web", count: 3, dyno_tier: tier)
    sign_in user
    patch "/dashboard/apps/#{the_app.id}/scaling", params: { scaling: { web: 5 } }
    # rescue_from PlanQuotaError redirects back with an alert flash
    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/Plan allows 3 small slots/i)
  end
end

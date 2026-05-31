# frozen_string_literal: true

require "rails_helper"

# Moved to Admin::DashboardController — route is now GET /admin.
RSpec.describe "Admin::Dashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  it "returns 404 for a non-admin (Devise authenticate block)" do
    sign_in users(:one)
    get admin_root_path
    expect(response).to have_http_status(:not_found)
  end

  it "renders the analytics page for an admin with 2FA enrolled" do
    admin = users(:admin)
    admin.update!(otp_required_for_login: true)
    sign_in admin
    get admin_root_path
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/revenue/i)
    expect(response.body).to match(/users/i)
    expect(response.body).to match(/apps/i)
    expect(response.body).to match(/promo redemptions/i)
  end

  # "excludes manual deposits from today's revenue" — the
  # DepositTransaction-based revenue metric was replaced with a
  # paid-invoice metric in 1.8. The test below covers the new path.

  it "counts paid invoices as today's revenue" do
    admin = users(:admin)
    admin.update!(otp_required_for_login: true)
    plan = Plan.find_or_create_by!(key: "solo") { |p| p.name = "Solo"; p.price_idr = 80_000 }
    user = users(:one)
    Invoice.create!(user: user, plan: plan, amount_idr: 80_000, amount_cents: 0,
                    status: :paid, paid_at: Time.current, kind: :renewal,
                    period_start: Date.current, period_end: Date.current.next_month,
                    period_label: "Test", reference_id: "INV-admin-spec-#{SecureRandom.hex(4)}")
    sign_in admin
    get admin_root_path
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/80\.000|80,000/)
  end
end

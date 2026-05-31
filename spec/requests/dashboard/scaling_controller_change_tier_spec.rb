# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Scaling change_tier", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    app_record.update!(status: :running) unless app_record.status == "running"
    sign_in user

    allow_any_instance_of(Dokku::Client).to receive(:run).and_return("")
    allow_any_instance_of(Dokku::Processes).to receive(:scale).and_return(nil)
    allow_any_instance_of(Dokku::Processes).to receive(:list).and_return({})
  end

  it "change_tier blocks when app has not deployed yet" do
    app_record.update!(status: :created)
    tier = dyno_tiers(:basic)
    post "/dashboard/apps/#{app_record.id}/scaling/change_tier", params: { dyno_tier_id: tier.id }
    expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
    expect(flash[:alert]).to match(/Deploy the app first/)
  end

  it "change_tier succeeds and creates allocation on running app" do
    tier = dyno_tiers(:standard)
    post "/dashboard/apps/#{app_record.id}/scaling/change_tier", params: { dyno_tier_id: tier.id }
    expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
    expect(flash[:notice]).to match(/Container size changed to standard/)
    expect(app_record.dyno_allocations.find_by(process_type: "web").dyno_tier).to eq(tier)
  end

  it "change_tier updates existing allocation in place" do
    old_tier = dyno_tiers(:basic)
    app_record.dyno_allocations.create!(process_type: "web", dyno_tier: old_tier, count: 2)

    new_tier = dyno_tiers(:standard)
    post "/dashboard/apps/#{app_record.id}/scaling/change_tier", params: { dyno_tier_id: new_tier.id }
    allocation = app_record.dyno_allocations.find_by(process_type: "web")
    expect(allocation.dyno_tier).to eq(new_tier)
    expect(allocation.count).to eq(2)
  end

  it "change_tier enforces max_per_user limit" do
    free = dyno_tiers(:free)
    free.update!(max_per_user: 1)
    other_app = AppRecord.create!(
      name: "other-free-app",
      server: app_record.server,
      team: app_record.team,
      creator: user,
      status: :running
    )
    other_app.dyno_allocations.create!(process_type: "web", dyno_tier: free, count: 1)

    post "/dashboard/apps/#{app_record.id}/scaling/change_tier", params: { dyno_tier_id: free.id }
    expect(flash[:alert]).to match(/only have 1 app on the free tier/)
  end

  it "change_tier scales workers to 0 when downgrading to non-scalable tier" do
    basic = dyno_tiers(:basic)
    basic.update!(scalable: false)
    app_record.process_scales.where(process_type: "worker").delete_all
    ps = app_record.process_scales.create!(process_type: "worker", count: 3)

    post "/dashboard/apps/#{app_record.id}/scaling/change_tier", params: { dyno_tier_id: basic.id }
    expect(ps.reload.count).to eq(0)
  ensure
    basic&.update!(scalable: true)
  end
end

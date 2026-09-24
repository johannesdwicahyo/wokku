require "rails_helper"

RSpec.describe "Resources frame builder", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:app_record) { app_records(:one) }
  before { sign_in users(:one) }

  it "renders one builder per process when the builder is on" do
    app_record.dyno_allocations.destroy_all
    app_record.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.5, memory_mb: 1024)
    app_record.dyno_allocations.create!(process_type: "worker", count: 1, cpu: 0.25, memory_mb: 512)
    get "/dashboard/apps/#{app_record.id}/resources", params: { deferred: 1 }
    expect(response.body).to include("processes[web][cpu]", "processes[worker][cpu]")
  end

  it "renders the legacy box picker when the builder is off" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(false)
    get "/dashboard/apps/#{app_record.id}/resources", params: { deferred: 1 }
    expect(response.body).to include("Change box size")
    expect(response.body).not_to include("processes[web][cpu]")
  end

  # Fix round 1 #2: the disk-almost-full warning email fires regardless of
  # resource_builder? (DiskUsageWarningJob), so the banner must too — not
  # just inside the builder's own form branch.
  it "renders the disk-almost-full banner even when the builder is off" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(false)
    app_record.update!(volume_disk_gb: 10)
    allow_any_instance_of(AppRecord).to receive(:volume_used_gb).and_return(9.5)
    get "/dashboard/apps/#{app_record.id}/resources", params: { deferred: 1 }
    expect(response.body).to include("Disk 95% full")
  end

  # Fix round 1 #3: a legacy tier-only allocation (dyno_tier set, cpu/
  # memory_mb nil — a.shape is nil) used to fall back to the Starter
  # preset (0.25 vCPU / 512 MB) regardless of the tier's real size, so
  # just opening the page and clicking Save would silently downsize it.
  it "renders a legacy tier allocation's real size, not the Starter fallback" do
    legacy_tier = create(:dyno_tier, memory_mb: 1024, cpu_shares: 0.5, sleeps: false)
    app_record.dyno_allocations.destroy_all
    app_record.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: legacy_tier)
    get "/dashboard/apps/#{app_record.id}/resources", params: { deferred: 1 }
    expect(response.body).to include('name="processes[web][memory_mb]" value="1024"')
    expect(response.body).to include('name="processes[web][cpu]" value="0.5"')
  end
end

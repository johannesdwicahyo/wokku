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
end

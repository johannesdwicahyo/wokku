require "rails_helper"

RSpec.describe "PATCH /dashboard/apps/:id/resources", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user)       { users(:one) }
  let(:app_record) { app_records(:one) }
  before { sign_in user }

  it "applies per-process shapes" do
    allow(Resources::ApplyChange).to receive(:call).and_return(Resources::ApplyChange::Result.new(ok: true))
    patch "/dashboard/apps/#{app_record.id}/resources", params: { processes: { web: { cpu: "0.5", memory_mb: "1024", count: "1" } }, volume_disk_gb: "3" }
    expect(Resources::ApplyChange).to have_received(:call).with(
      app: app_record, user: user, processes: { "web" => { "cpu" => "0.5", "memory_mb" => "1024", "count" => "1" } }, volume_disk_gb: "3"
    )
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/resources")
  end

  it "shows the rejection reason" do
    allow(Resources::ApplyChange).to receive(:call).and_return(Resources::ApplyChange::Result.new(ok: false, error: "Server capacity is full"))
    patch "/dashboard/apps/#{app_record.id}/resources", params: { processes: { web: { cpu: "4", memory_mb: "8192", count: "1" } } }
    follow_redirect!
    expect(response.body).to include("Server capacity is full")
  end
end

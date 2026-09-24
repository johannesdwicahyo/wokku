require "rails_helper"

# The dashboard databases controller (Dashboard::DatabasesController) is
# mounted at /dashboard/addons via `resources :addons, controller:
# "databases"` (config/routes.rb) — there is no /dashboard/databases path
# in this app, so the resize member route lands under /dashboard/addons.
RSpec.describe "PATCH /dashboard/addons/:id/resize", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { users(:one) }
  before { sign_in user }

  it "delegates to ResizeService and reports the error" do
    db = create(:database_service, server: app_records(:one).server, cpu: 0.25, memory_mb: 512, disk_gb: 10)
    db.app_databases.create!(app_record: app_records(:one), alias_name: "DATABASE")
    allow(Resources::ResizeService).to receive(:call).and_return(Resources::ApplyChange::Result.new(ok: false, error: "Disk can only grow"))
    patch "/dashboard/addons/#{db.id}/resize", params: { cpu: "0.25", memory_mb: "512", disk_gb: "5" }
    follow_redirect!
    expect(response.body).to include("Disk can only grow")
  end
end

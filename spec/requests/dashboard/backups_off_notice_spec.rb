require "rails_helper"

# Self-host: database backups need an S3-compatible bucket. Until the admin
# adds one, the databases page says so (nothing is backed up silently).
RSpec.describe "Backups-off notice", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    allow(Wokku).to receive(:cloud?).and_return(false)
    TeamMembership.find_or_create_by!(user: users(:admin), team: teams(:one)) { |m| m.role = :admin }
  end

  it "tells the admin backups are off and links to the bucket settings" do
    sign_in users(:admin)
    get "/dashboard/addons"
    expect(response.body).to include("data-backups-off")
    expect(response.body).to include("/backup_destination/edit")
  end

  it "is gone once every server backs up to a bucket" do
    Server.find_each { |s| s.create_backup_destination!(provider: "s3", bucket: "b", enabled: true) }
    sign_in users(:admin)
    get "/dashboard/addons"
    expect(response.body).not_to include("data-backups-off")
  end

  it "is not shown to non-admins or on wokku.cloud" do
    sign_in users(:one)
    get "/dashboard/addons"
    expect(response.body).not_to include("data-backups-off")
    allow(Wokku).to receive(:cloud?).and_return(true)
    sign_in users(:admin)
    get "/dashboard/addons"
    expect(response.body).not_to include("data-backups-off")
  end
end

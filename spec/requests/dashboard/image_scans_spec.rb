require "rails_helper"

RSpec.describe "Dashboard::ImageScans", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:team) { user.teams.first }
  let(:server) { create(:server, team: team) }
  let(:record) { create(:app_record, team: team, server: server, status: :running, name: "shop") }
  let(:findings) do
    [ { "id" => "CVE-2024-1", "package" => "openssl", "installed" => "1", "fixed" => "2", "severity" => "HIGH", "title" => "bad ssl" },
      { "id" => "DSA-9", "package" => "zlib", "installed" => "1", "fixed" => "", "severity" => "LOW", "title" => "meh" } ]
  end

  before do
    sign_in user
    allow(Wokku.config).to receive(:image_scans?).and_return(true)
    d = create(:deploy, :succeeded, app_record: record, image_ref: "127.0.0.1:5000/x/shop:2", finished_at: 1.hour.ago)
    Release.create!(app_record: record, deploy: d, version: 2)
  end

  def scan!(ref, **attrs)
    ImageScan.create!({ app_record: record, server: server, image_ref: ref, status: :succeeded, counts: { "high" => 1 }, findings: findings }.merge(attrs))
  end

  it "renders findings of the current image, linking CVE ids only" do
    scan!("127.0.0.1:5000/x/shop:2")
    get dashboard_app_image_scan_path(record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://avd.aquasec.com/nvd/cve-2024-1", "DSA-9", "openssl")
    expect(response.body).not_to include("nvd/dsa-9")
  end

  it "filters to fixable" do
    scan!("127.0.0.1:5000/x/shop:2")
    get dashboard_app_image_scan_path(record, fixable: 1)
    expect(response.body).to include("openssl")
    expect(response.body).not_to include("zlib")
  end

  it "ignores scans of a superseded image" do
    scan!("127.0.0.1:5000/x/shop:1")
    get dashboard_app_image_scan_path(record)
    expect(response.body).to include("First scan after the next deploy")
    expect(response.body).not_to include("openssl")
  end

  it "lets a viewer read" do
    scan!("127.0.0.1:5000/x/shop:2")
    viewer = create(:user)
    TeamMembership.create!(user: viewer, team: team, role: :viewer)
    sign_in viewer
    get dashboard_app_image_scan_path(record)
    expect(response).to have_http_status(:ok)
  end

  it "refuses another team's user" do
    scan!("127.0.0.1:5000/x/shop:2")
    sign_in create(:user)
    get dashboard_app_image_scan_path(record)
    expect(response).not_to have_http_status(:ok)
  end

  it "shows Scanning… while pending and the failure copy when failed" do
    scan!("127.0.0.1:5000/x/shop:2", status: :pending, findings: [])
    get dashboard_app_image_scan_path(record)
    expect(response.body).to include("Scanning…")
    ImageScan.delete_all
    scan!("127.0.0.1:5000/x/shop:2", status: :failed, findings: [])
    get dashboard_app_image_scan_path(record)
    expect(response.body).to include("Scan failed · retry tonight")
  end

  it "does not link malformed advisory ids" do
    scan!("127.0.0.1:5000/x/shop:2", findings: [ findings[0].merge("id" => "CVE-evil") ])
    get dashboard_app_image_scan_path(record)
    expect(response.body).not_to include("avd.aquasec.com")
  end

  it "redirects when the feature is off" do
    allow(Wokku.config).to receive(:image_scans?).and_return(false)
    get dashboard_app_image_scan_path(record)
    expect(response).to redirect_to(dashboard_app_path(record))
  end

  describe "app overview panel" do
    it "shows the current image's scan, absent when disabled" do
      scan!("127.0.0.1:5000/x/shop:2")
      get dashboard_app_path(record)
      expect(response.body).to include("Security · image")
      expect(Nokogiri::HTML(response.body).text.squish).to include("1 High")
      allow(Wokku.config).to receive(:image_scans?).and_return(false)
      get dashboard_app_path(record)
      expect(response.body).not_to include("Security · image")
    end
  end
end

require "rails_helper"

RSpec.describe Release do
  it "auto-increments version on create" do
    app = app_records(:one)
    release = Release.create!(app_record: app, description: "test release")
    expect(release.version).to be > 0
  end

  it "version is unique per app_record" do
    release = releases(:one)
    duplicate = Release.new(app_record: release.app_record, version: release.version)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:version]).to include("has already been taken")
  end

  it "links both ways when a webhook creates the release for an existing deploy" do
    app = app_records(:one)
    deploy = app.deploys.create!(status: :pending)
    release = app.releases.create!(deploy: deploy, description: "commit msg")
    expect(deploy.reload.release_id).to eq(release.id)
  end

  it "links both ways when the dashboard creates the deploy for an existing release" do
    app = app_records(:one)
    release = app.releases.create!(description: "Manual deploy via dashboard")
    deploy = app.deploys.create!(release: release, status: :pending)
    expect(release.reload.deploy_id).to eq(deploy.id)
  end
end

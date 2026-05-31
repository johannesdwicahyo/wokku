require "rails_helper"

RSpec.describe AppRecord, "git remote URLs" do
  let(:app) { app_records(:one) }

  around do |ex|
    orig = ENV["WOKKU_GIT_HOST"]
    ex.run
  ensure
    ENV["WOKKU_GIT_HOST"] = orig
  end

  it "defaults git_remote_url to wokku.cloud" do
    ENV.delete("WOKKU_GIT_HOST")
    expect(app.git_remote_url).to eq("git@wokku.cloud:#{app.name}")
  end

  it "honors WOKKU_GIT_HOST (e.g. for self-hosted installs)" do
    ENV["WOKKU_GIT_HOST"] = "wokku.example.org"
    expect(app.git_remote_url).to eq("git@wokku.example.org:#{app.name}")
  end

  it "direct_git_remote_url still exposes the underlying Dokku host" do
    expect(app.direct_git_remote_url).to eq("dokku@#{app.server.host}:#{app.name}")
  end
end

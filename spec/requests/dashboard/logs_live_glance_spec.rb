# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Logs live glance", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:path) { "/dashboard/apps/#{app_record.id}/logs" }

  # Naming pinned: wokkud/internal/lifecycle/converge.go:292 ServiceName =
  # "wokku-<app>-<proc>"; Swarm task containers are "<service>.<slot>.<task>"
  # (app/services/hosts/container_names.rb header).
  def seed(proc, line, n: 1)
    n.times do |i|
      Log.create!(server: app_record.server, app_record: app_record, ts: Time.current + i,
                  container: "wokku-#{app_record.name}-#{proc}.1.abc#{i}", line: "#{line}#{i}")
    end
  end

  before do
    sign_in user
    create(:dyno_allocation, app_record: app_record, process_type: "web")
    create(:dyno_allocation, app_record: app_record, process_type: "worker")
  end

  it "returns at most `lines` lines" do
    seed("web", "w", n: 60)
    get path, params: { glance: true, lines: 50 }
    expect(response.body.scan(/<div>w\d+<\/div>/).size).to eq(50)
  end

  it "filters by process" do
    seed("web", "webline")
    seed("worker", "workerline")
    get path, params: { glance: true, process: "worker" }
    expect(response.body).to include("workerline")
    expect(response.body).not_to include("webline")
  end

  it "ignores an unknown process" do
    seed("web", "webline")
    seed("worker", "workerline")
    get path, params: { glance: true, process: "bogus" }
    expect(response.body).to include("webline").and include("workerline")
  end

  it "clamps lines to 200" do
    seed("web", "w", n: 210)
    get path, params: { glance: true, lines: 10_000 }
    expect(response.body.scan(/<div>w\d+<\/div>/).size).to eq(200)
  end

  it "uses the live frame id when asked" do
    get path, params: { glance: true, frame: "app_live_log" }
    expect(response.body).to include('id="app_live_log"')
  end

  it "lets a viewer read" do
    viewer = User.create!(email: "viewer-glance@example.com", password: "password123456")
    TeamMembership.create!(user: viewer, team: app_record.team, role: :viewer)
    sign_in viewer
    get path, params: { glance: true }
    expect(response).to have_http_status(:success)
  end
end

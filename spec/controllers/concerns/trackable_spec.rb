require "rails_helper"

# Trackable is included in Api::V1::BaseController and Dashboard::BaseController.
# We test it through the API layer (no browser session needed).
# Dokku SSH calls are stubbed to avoid real network connections in tests.
RSpec.describe Trackable, type: :request do
  let!(:user) { User.create!(email: "trackable_test@example.com", password: "password123456") }
  let!(:team) { Team.create!(name: "Trackable Test Team", owner: user) }
  let!(:membership) { TeamMembership.create!(user: user, team: team, role: :admin) }
  let!(:server) { Server.create!(name: "track-server", host: "10.0.0.1", team: team) }
  let(:token_pair) { ApiToken.create_with_token!(user: user, name: "trackable-token") }
  let(:plain_token) { token_pair.last }
  let(:auth_headers) { { "Authorization" => "Bearer #{plain_token}" } }

  before do
    plain_token
    # Stub Dokku::Apps#create so no SSH connection is attempted.
    allow_any_instance_of(Dokku::Apps).to receive(:create).and_return(nil)
  end

  it "creates an Activity record when the track helper is called" do
    expect {
      post api_v1_apps_path,
           params: { name: "tracked-app", server_id: server.id },
           headers: auth_headers
    }.to change { Activity.count }.by(1)

    activity = Activity.order(:created_at).last
    expect(activity.action).to eq("app.created")
    expect(activity.user).to eq(user)
    expect(activity.team).to eq(team)
  end

  it "records the correct target name" do
    post api_v1_apps_path,
         params: { name: "mytracked", server_id: server.id },
         headers: auth_headers

    activity = Activity.order(:created_at).last
    expect(activity.target_name).to eq("mytracked")
  end

  it "records target_type as AppRecord" do
    post api_v1_apps_path,
         params: { name: "typed-app", server_id: server.id },
         headers: auth_headers

    activity = Activity.order(:created_at).last
    expect(activity.target_type).to eq("AppRecord")
  end

  it "creates no Activity when the action does not call track" do
    # GET index does not call track
    expect {
      get api_v1_apps_path, headers: auth_headers
    }.not_to change { Activity.count }
  end
end

# frozen_string_literal: true

require "rails_helper"

# Registering the first phone turns push on for the user's teams (on-call
# events) unless a team already has its own push rule.
RSpec.describe "Device registration push defaults", type: :request do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }
  let(:headers) { api_v1_headers(user) }

  before { user.device_tokens.destroy_all }

  def register(token, provider: nil)
    post "/api/v1/devices", params: { token: token, platform: "ios", provider: provider }.compact, headers: headers, as: :json
  end

  it "creates a push rule with the on-call events on the first device" do
    team.notifications.where(channel: :push).delete_all
    register("tok-a")
    rule = team.notifications.find_by(channel: :push)
    expect(rule.events).to match_array(%w[app_down app_recovered app_crashed deploy_failed backup_failed])
  end

  it "does not add a second rule for a second device or override an existing one" do
    team.notifications.where(channel: :push).delete_all
    team.notifications.create!(channel: :push, events: [ "deploy_succeeded" ])
    register("tok-a")
    register("tok-b")
    expect(team.notifications.where(channel: :push).pluck(:events)).to eq([ [ "deploy_succeeded" ] ])
  end

  it "stores the provider, defaulting to expo" do
    register("tok-expo")
    register("tok-apns", provider: "apns")
    expect(DeviceToken.find_by(token: "tok-expo").provider).to eq("expo")
    expect(DeviceToken.find_by(token: "tok-apns").provider).to eq("apns")
  end

  it "rejects an unknown provider" do
    register("tok-x", provider: "fcm")
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

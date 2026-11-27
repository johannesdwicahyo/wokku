# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Notifications", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  # team must be created EAGERLY so current_user.teams.first resolves
  # before the request hits the controller (let is lazy; current_team
  # would otherwise be nil).
  let!(:team) do
    t = create(:team, owner: user)
    create(:team_membership, team: t, user: user, role: :admin)
    t
  end

  before { sign_in user }

  describe "GET /dashboard/notifications" do
    it "renders" do
      get "/dashboard/notifications"
      expect(response).to have_http_status(:ok)
    end

    it "offers the image_scan_critical event only when image scans are on" do
      allow(Wokku.config).to receive(:image_scans?).and_return(false)
      get "/dashboard/notifications"
      expect(response.body).not_to include('value="image_scan_critical"')
      allow(Wokku.config).to receive(:image_scans?).and_return(true)
      get "/dashboard/notifications"
      expect(response.body).to include('value="image_scan_critical"')
    end
  end

  describe "POST /dashboard/notifications (create)" do
    it "creates a slack notification rule" do
      expect {
        post "/dashboard/notifications", params: {
          notification: {
            channel: "slack",
            events: %w[deploy_succeeded deploy_failed],
            config: { url: "https://hooks.slack.com/services/T/B/X" }
          }
        }
      }.to change { team.notifications.count }.by(1)
      expect(response).to redirect_to("/dashboard/notifications")
    end

    # Note: the model has `validates :events, presence: true` but Rails'
    # presence validator accepts non-nil empty arrays. Empty-events
    # notifications save but never fire because NotifyJob checks
    # `events.include?(event)`. Not a bug worth fixing here, but worth
    # documenting in case a future contributor wonders.
  end

  describe "POST /dashboard/notifications/:id/test" do
    let(:notification) do
      Notification.create!(team: team, channel: :slack,
                           config: { "url" => "https://hooks.slack.com/services/T/B/X" },
                           events: %w[deploy_succeeded])
    end

    it "enqueues NotifyJob with sentinel deploy_id=0" do
      expect {
        post "/dashboard/notifications/#{notification.id}/test"
      }.to have_enqueued_job(NotifyJob).with(notification.id, "deploy_succeeded", 0)
      expect(response).to redirect_to("/dashboard/notifications")
    end

    it "uses the first subscribed event for the test message" do
      notification.update!(events: %w[backup_failed deploy_succeeded])
      expect {
        post "/dashboard/notifications/#{notification.id}/test"
      }.to have_enqueued_job(NotifyJob).with(notification.id, "backup_failed", 0)
    end

    it "rejects when not authenticated" do
      sign_out user
      post "/dashboard/notifications/#{notification.id}/test"
      expect(response.status).to be_in([ 302, 401 ])
    end
  end

  describe "DELETE /dashboard/notifications/:id" do
    let!(:notification) do
      Notification.create!(team: team, channel: :slack,
                           config: { "url" => "x" }, events: %w[deploy_succeeded])
    end

    it "removes the rule" do
      expect {
        delete "/dashboard/notifications/#{notification.id}"
      }.to change { team.notifications.count }.by(-1)
    end
  end
end

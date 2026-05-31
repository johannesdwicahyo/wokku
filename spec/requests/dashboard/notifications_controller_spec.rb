# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Notifications (fixture-based)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)         { users(:two) }
  let(:notification) { notifications(:two) }

  it "redirects to login when not authenticated on index" do
    get "/dashboard/notifications"
    expect(response).to have_http_status(:redirect)
  end

  it "shows notifications index when authenticated" do
    sign_in user
    get "/dashboard/notifications"
    expect(response).to have_http_status(:success)
  end

  it "redirects to login when not authenticated on create" do
    post "/dashboard/notifications", params: {
      notification: { channel: 0, events: [ "deploy.succeeded" ], config: {} }
    }
    expect(response).to have_http_status(:redirect)
  end

  it "redirects to login when not authenticated on destroy" do
    delete "/dashboard/notifications/#{notification.id}"
    expect(response).to have_http_status(:redirect)
  end

  it "destroys notification when authenticated" do
    sign_in user
    n = notification
    expect {
      delete "/dashboard/notifications/#{n.id}"
    }.to change { Notification.count }.by(-1)
    expect(response).to redirect_to("/dashboard/notifications")
  end
end

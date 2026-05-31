# frozen_string_literal: true

require "rails_helper"

# Moved to Admin::UsersController — paths are now /admin/users/*.
RSpec.describe "Admin::Users", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { users(:admin) } # otp_required_for_login: true in fixture
  let(:user) { users(:one) }

  before do
    user.update_columns(deletion_scheduled_at: nil, deleted_at: nil)
  end

  describe "auth" do
    it "returns 404 for a non-admin (Devise authenticate block)" do
      sign_in users(:one)
      get "/admin/users"
      expect(response).to have_http_status(:not_found)
    end

    it "redirects unauthenticated users from index" do
      get "/admin/users"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /admin/users" do
    it "renders the user list" do
      sign_in admin
      get "/admin/users"
      expect(response).to have_http_status(:success)
      expect(response.body).to match(user.email)
    end

    it "supports searching by email" do
      sign_in admin
      get "/admin/users", params: { q: user.email }
      expect(response).to have_http_status(:success)
      expect(response.body).to match(user.email)
    end

    it "shows no-results state when search has no match" do
      sign_in admin
      get "/admin/users", params: { q: "nonexistent-xyz-abc@nope.example" }
      expect(response).to have_http_status(:success)
      expect(response.body).to match(/no users found/i)
    end
  end

  describe "GET /admin/users/:id" do
    it "renders the show page" do
      sign_in admin
      get "/admin/users/#{user.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to match(user.email)
    end
  end

  describe "DELETE /admin/users/:id" do
    it "schedules soft deletion for a user" do
      sign_in admin
      delete "/admin/users/#{user.id}", params: { hard: false }
      expect(response).to have_http_status(:redirect)
      user.reload
      expect(user.deletion_pending?).to be_truthy
      user.update_columns(deletion_scheduled_at: nil)
    end

    it "enqueues HardDeleteAccountJob for hard delete" do
      sign_in admin
      expect {
        delete "/admin/users/#{user.id}", params: { hard: true }
      }.to have_enqueued_job(HardDeleteAccountJob)
      expect(response).to have_http_status(:redirect)
    end

    it "returns 404 for a non-admin (Devise authenticate block)" do
      sign_in users(:one)
      delete "/admin/users/#{user.id}", params: { hard: false }
      expect(response).to have_http_status(:not_found)
      expect(user.reload.deletion_scheduled_at).to be_nil
    end
  end
end

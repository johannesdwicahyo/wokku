# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::AccountDeletions", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:one) }

  before do
    user.update_columns(deletion_scheduled_at: nil, deleted_at: nil)
  end

  describe "authentication" do
    it "GET show redirects to login when unauthenticated" do
      get "/dashboard/account_deletion"
      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "POST create redirects to login when unauthenticated" do
      post "/dashboard/account_deletion"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET show" do
    it "renders confirmation page" do
      sign_in user
      get "/dashboard/account_deletion"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("/dashboard/account_deletion")
    end
  end

  describe "POST create" do
    it "with wrong email redirects back with alert" do
      sign_in user
      post "/dashboard/account_deletion", params: { confirmation_email: "wrong@example.com" }
      expect(response).to redirect_to(dashboard_account_deletion_path)
      follow_redirect!
      expect(response).to have_http_status(:success)
      expect(user.reload.deletion_scheduled_at).to be_nil
    end

    it "with correct email schedules deletion and signs out" do
      sign_in user
      post "/dashboard/account_deletion", params: { confirmation_email: user.email }
      expect(response).to redirect_to(root_path)
      user.reload
      expect(user.deletion_pending?).to be_truthy
      expect(user.deletion_scheduled_at.to_i).to be_within(10).of(3.days.from_now.to_i)
    end

    it "enqueues AccountMailer when email matches" do
      sign_in user
      expect {
        post "/dashboard/account_deletion", params: { confirmation_email: user.email }
      }.to have_enqueued_mail
    end

    it "is idempotent for already-pending user" do
      user.update_columns(deletion_scheduled_at: 2.days.from_now)
      original_scheduled = user.deletion_scheduled_at

      sign_in user
      post "/dashboard/account_deletion", params: { confirmation_email: user.email }
      expect(user.reload.deletion_scheduled_at.to_i).to be_within(5).of(original_scheduled.to_i)
    end
  end

  describe "DELETE destroy" do
    it "cancels a pending deletion for self-service recovery" do
      user.schedule_deletion!
      expect(user.reload.deletion_pending?).to be_truthy
      sign_in user
      delete "/dashboard/account_deletion"
      expect(response).to redirect_to(dashboard_profile_path)
      expect(user.reload.deletion_scheduled_at).to be_nil
    end

    it "is a no-op when no deletion is scheduled" do
      sign_in user
      delete "/dashboard/account_deletion"
      expect(response).to redirect_to(dashboard_profile_path)
      expect(flash[:alert].to_s).to match(/no deletion/i)
    end
  end
end

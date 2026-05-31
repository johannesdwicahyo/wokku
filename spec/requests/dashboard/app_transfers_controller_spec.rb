# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::AppTransfers", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:owner) { users(:one) }
  let(:target) { users(:two) }
  let(:app_record) { app_records(:one) }

  describe "POST apps#transfer" do
    it "creates a pending AppTransfer instead of flipping ownership" do
      sign_in owner
      expect {
        expect {
          post transfer_dashboard_app_path(app_record), params: { email: target.email }
        }.to have_enqueued_mail
      }.to change { AppTransfer.count }.by(1)

      transfer = AppTransfer.last
      expect(transfer.status).to eq("pending")
      expect(transfer.from_user_id).to eq(owner.id)
      expect(transfer.to_user_id).to eq(target.id)
      expect(app_record.reload.team_id).to eq(owner.teams.first.id)
    end

    it "rejects a second pending transfer for the same app" do
      sign_in owner
      AppTransfer.create!(app_record: app_record, from_user: owner, to_user: target)
      expect {
        post transfer_dashboard_app_path(app_record), params: { email: target.email }
      }.not_to change { AppTransfer.count }
      expect(flash[:alert].to_s).to match(/already pending/i)
    end
  end

  describe "POST accept" do
    it "rotates ownership and marks transfer accepted" do
      transfer = AppTransfer.create!(app_record: app_record, from_user: owner, to_user: target)
      sign_in target

      expect(AppOwnershipTransfer).to receive(:call).with(app: app_record, target_user: target)
        .and_return(AppOwnershipTransfer::Result.new(ok?: true, error: nil))

      post accept_dashboard_app_transfer_path(transfer)
      expect(response).to have_http_status(:redirect)
      expect(transfer.reload.status).to eq("accepted")
      expect(transfer.accepted_at).not_to be_nil
    end
  end

  describe "POST decline" do
    it "marks declined and leaves ownership untouched" do
      transfer = AppTransfer.create!(app_record: app_record, from_user: owner, to_user: target)
      sign_in target
      post decline_dashboard_app_transfer_path(transfer)
      expect(response).to have_http_status(:redirect)
      expect(transfer.reload.status).to eq("declined")
      expect(app_record.reload.team_id).to eq(owner.teams.first.id)
    end
  end

  describe "DELETE destroy" do
    it "lets the source-owner cancel their pending transfer" do
      transfer = AppTransfer.create!(app_record: app_record, from_user: owner, to_user: target)
      sign_in owner
      delete dashboard_app_transfer_path(transfer)
      expect(response).to have_http_status(:redirect)
      expect(transfer.reload.status).to eq("cancelled")
    end
  end

  describe "non-target authorization" do
    it "non-target cannot accept" do
      transfer = AppTransfer.create!(app_record: app_record, from_user: owner, to_user: target)
      sign_in users(:admin)
      post accept_dashboard_app_transfer_path(transfer)
      expect(response).to have_http_status(:redirect)
      expect(transfer.reload.status).to eq("pending")
    end
  end
end

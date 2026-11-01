# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AppTransfersController", type: :request do
  let(:sender) { users(:one) }
  let(:recipient) { users(:two) }
  let(:app_record) { app_records(:one) }
  let!(:transfer) { AppTransfer.create!(app_record: app_record, from_user: sender, to_user: recipient) }
  let(:as_sender) { { "Authorization" => "Bearer #{api_v1_token_for(sender)}" } }
  let(:as_recipient) { { "Authorization" => "Bearer #{api_v1_token_for(recipient)}" } }

  it "lists incoming transfers for the recipient and outgoing for the sender" do
    get "/api/v1/app_transfers", headers: as_recipient
    expect(JSON.parse(response.body)["incoming"].map { |t| t["id"] }).to eq([ transfer.id ])

    get "/api/v1/app_transfers", headers: as_sender
    body = JSON.parse(response.body)
    expect(body["outgoing"].first).to include("id" => transfer.id, "app_name" => app_record.name, "to_email" => recipient.email)
  end

  it "accepts as the recipient" do
    allow(AppOwnershipTransfer).to receive(:call).and_return(double(ok?: true))

    post "/api/v1/app_transfers/#{transfer.id}/accept", headers: as_recipient

    expect(response).to have_http_status(:ok)
    expect(transfer.reload.status).to eq("accepted")
    expect(AppOwnershipTransfer).to have_received(:call).with(app: app_record, target_user: recipient)
  end

  it "refuses accept from the sender" do
    post "/api/v1/app_transfers/#{transfer.id}/accept", headers: as_sender
    expect(response).to have_http_status(:forbidden)
    expect(transfer.reload.status).to eq("pending")
  end

  it "declines as the recipient" do
    post "/api/v1/app_transfers/#{transfer.id}/decline", headers: as_recipient
    expect(response).to have_http_status(:ok)
    expect(transfer.reload.status).to eq("declined")
  end

  it "cancels as the sender" do
    delete "/api/v1/app_transfers/#{transfer.id}", headers: as_sender
    expect(response).to have_http_status(:ok)
    expect(transfer.reload.status).to eq("cancelled")
  end

  it "answers 409 transfer_not_pending once the transfer is answered" do
    transfer.update!(status: "declined")
    post "/api/v1/app_transfers/#{transfer.id}/accept", headers: as_recipient
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)["error_code"]).to eq("transfer_not_pending")
  end

  it "hides a transfer from anyone who isn't the sender or recipient" do
    outsider = User.create!(email: "outsider@example.com", password: "password123456")
    post "/api/v1/app_transfers/#{transfer.id}/accept", headers: { "Authorization" => "Bearer #{api_v1_token_for(outsider)}" }
    expect(response).to have_http_status(:not_found)
  end
end

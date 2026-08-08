# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::SshKeysController", type: :request do
  let(:user) { users(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns user's keys" do
    user.ssh_public_keys.create!(name: "laptop", public_key: "ssh-ed25519 AAAAFa user@host", fingerprint: "SHA256:aaa")
    get "/api/v1/ssh_keys", headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body.any? { |k| k["name"] == "laptop" }).to be_truthy
  end

  it "create returns 422 when public key is not valid" do
    post "/api/v1/ssh_keys",
      params: { name: "bogus", public_key: "not a real key" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "create returns 422 on validation error" do
    post "/api/v1/ssh_keys",
      params: { name: "", public_key: "" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "destroy removes a key" do
    k = user.ssh_public_keys.create!(name: "delme", public_key: "ssh-ed25519 AAAAdel user@host", fingerprint: "SHA256:del")
    expect {
      delete "/api/v1/ssh_keys/#{k.id}", headers: headers
    }.to change { user.ssh_public_keys.count }.by(-1)
    expect(response).to have_http_status(:success)
  end
end

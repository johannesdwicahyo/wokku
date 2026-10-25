require "rails_helper"

RSpec.describe "POST /api/v1/auth/mobile/token", type: :request do
  let(:user) { create(:user) }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
  let!(:code) { MobileAuthCode.issue!(user: user, code_challenge: challenge) }

  it "exchanges the code for an API token" do
    post "/api/v1/auth/mobile/token", params: { code: code, code_verifier: verifier }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["token"]).to be_present
    expect(response.parsed_body["user"]).to include("id" => user.id, "email" => user.email)
    expect(user.api_tokens.last.name).to start_with("ios-")
  end

  it "uses token_name when given" do
    post "/api/v1/auth/mobile/token", params: { code: code, code_verifier: verifier, token_name: "Jane's iPhone" }, as: :json
    expect(user.api_tokens.last.name).to eq("Jane's iPhone")
  end

  it "refuses a replay with the same generic 401" do
    post "/api/v1/auth/mobile/token", params: { code: code, code_verifier: verifier }, as: :json
    expect {
      post "/api/v1/auth/mobile/token", params: { code: code, code_verifier: verifier }, as: :json
    }.not_to change(ApiToken, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error_code"]).to eq("invalid_token")
  end

  it "gives the same body for a wrong verifier and an unknown code" do
    post "/api/v1/auth/mobile/token", params: { code: code, code_verifier: "y" * 43 }, as: :json
    wrong = response.parsed_body
    post "/api/v1/auth/mobile/token", params: { code: "unknown", code_verifier: verifier }, as: :json
    expect(response.parsed_body).to eq(wrong)
    expect(response).to have_http_status(:unauthorized)
  end

  it "422s without code or verifier" do
    post "/api/v1/auth/mobile/token", params: { code: code }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error_code"]).to eq("invalid_params")
  end

  it "422s a verifier outside 43..128 chars" do
    post "/api/v1/auth/mobile/token", params: { code: code, code_verifier: "short" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

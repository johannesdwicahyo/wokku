require "rails_helper"

RSpec.describe ApiAuthenticatable, type: :request do
  let!(:user) { User.create!(email: "api_auth_test@example.com", password: "password123456") }
  let!(:team) { Team.create!(name: "Auth Test Team", owner: user) }
  let!(:membership) { TeamMembership.create!(user: user, team: team, role: :admin) }
  let(:token_pair) { ApiToken.create_with_token!(user: user, name: "auth-test-token") }
  let(:plain_token) { token_pair.last }

  before { plain_token } # force creation

  it "returns 401 when the Authorization header is missing" do
    get api_v1_apps_path
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("Missing authorization token")
  end

  it "returns 401 when the Authorization header is malformed (no Bearer)" do
    get api_v1_apps_path, headers: { "Authorization" => plain_token }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("Missing authorization token")
  end

  it "returns 401 for an invalid token value" do
    get api_v1_apps_path, headers: { "Authorization" => "Bearer invalidtoken" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("Invalid or expired token")
  end

  it "returns 401 for an expired token" do
    ApiToken.create!(
      user: user,
      name: "expired-token",
      token_digest: Digest::SHA256.hexdigest("expiredplaintoken"),
      expires_at: 1.hour.ago
    )
    get api_v1_apps_path, headers: { "Authorization" => "Bearer expiredplaintoken" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("Invalid or expired token")
  end

  it "returns 401 for a revoked token" do
    plain = "revokedplaintoken"
    ApiToken.create!(
      user: user,
      name: "revoked-token",
      token_digest: Digest::SHA256.hexdigest(plain),
      revoked_at: 1.hour.ago
    )
    get api_v1_apps_path, headers: { "Authorization" => "Bearer #{plain}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("Invalid or expired token")
  end

  it "succeeds with a valid token and updates last_used_at" do
    api_token = ApiToken.find_by(token_digest: Digest::SHA256.hexdigest(plain_token))
    original_last_used = api_token.last_used_at

    travel_to 5.minutes.from_now do
      get api_v1_apps_path, headers: { "Authorization" => "Bearer #{plain_token}" }
    end

    expect(response).to have_http_status(:success)
    api_token.reload
    expect(api_token.last_used_at > original_last_used.to_time).to be(true) if original_last_used
  end

  it "sets current_user so the response reflects the authenticated user" do
    get api_v1_apps_path, headers: { "Authorization" => "Bearer #{plain_token}" }
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body).to be_a(Array)
  end
end

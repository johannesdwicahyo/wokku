require "rails_helper"

RSpec.describe "Sign-in page", type: :request do
  before { get new_user_session_path }

  it "renders brutalist, GitHub-first, with continuity microcopy" do
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("bg-bg").or include("text-ink")
    expect(response.body).to include("repos or code").or include("repo atau kode")
    # Check GitHub OAuth path appears before Google OAuth path (not Google Fonts)
    ghi = response.body.index("user_github_omniauth_authorize_path") ||
          response.body.index("/users/auth/github")
    goi = response.body.index("user_google_oauth2_omniauth_authorize_path") ||
          response.body.index("/users/auth/google_oauth2")
    expect(ghi).to be_present
    expect(goi).to be_present
    expect(ghi).to be < goi
  end
end

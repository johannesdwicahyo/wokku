require "rails_helper"

# Callout boxes (:::callout note … :::) must render their text — they
# rendered as an empty "Note" box on every docs page (2026-11-11).
RSpec.describe "Docs callouts", type: :request do
  it "renders the callout's text inside the box" do
    get "/docs/databases/backups"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Need nightly backups for a shared database?")
  end
end

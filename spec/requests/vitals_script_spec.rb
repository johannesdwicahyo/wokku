require "rails_helper"

RSpec.describe "GET /v.js", type: :request do
  it "serves the vitals JS with javascript content-type" do
    get "/v.js"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/javascript")
  end

  it "sets a long-lived Cache-Control header" do
    get "/v.js"
    expect(response.headers["Cache-Control"]).to include("public")
    expect(response.headers["Cache-Control"]).to include("max-age=31536000")
  end

  it "includes the beacon endpoint string" do
    get "/v.js"
    expect(response.body).to include("/vitals/ingest")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/openapi.yaml", type: :request do
  it "serves the configured contract without a token" do
    get "/api/v1/openapi.yaml"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/yaml")
    expect(response.body.b).to eq(File.binread(Wokku.config.openapi_path))
  end

  # Test env renders routing errors as 404 (show_exceptions :rescuable); if
  # it raises ActionController::RoutingError instead, assert that raise.
  it "is read-only" do
    post "/api/v1/openapi.yaml"
    expect(response).to have_http_status(:not_found)
  end
end

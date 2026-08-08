# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::TemplatesController", type: :request do
  let(:user) { User.create!(email: "templates-test@example.com", password: "password123456") }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns 401 without token" do
    get api_v1_templates_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "show returns 401 without token" do
    get api_v1_template_path("rails")
    expect(response).to have_http_status(:unauthorized)
  end

  it "index returns templates list" do
    get api_v1_templates_path, headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body).to have_key("templates")
    expect(body).to have_key("categories")
    expect(body["templates"]).to be_a(Array)
  end

  it "index filters by query" do
    get api_v1_templates_path, params: { q: "rails" }, headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body).to have_key("templates")
  end

  it "index filters by category" do
    get api_v1_templates_path, params: { category: "backend" }, headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body).to have_key("templates")
  end

  it "show returns template details" do
    get api_v1_template_path("rails"), headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body.key?("slug") || body.key?("name")).to be_truthy
  end

  it "show returns 404 for unknown template" do
    get api_v1_template_path("nonexistent-template-xyz"), headers: headers
    expect(response).to have_http_status(:not_found)
  end
end

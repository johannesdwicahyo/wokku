# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::TemplatesController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:server) { servers(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns all templates when no query" do
    allow_any_instance_of(TemplateRegistry).to receive(:all).and_return([ { slug: "n8n", name: "n8n" } ])
    allow_any_instance_of(TemplateRegistry).to receive(:categories).and_return([ "automation" ])

    get "/api/v1/templates", headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["templates"].length).to eq(1)
    expect(body["categories"]).to include("automation")
  end

  it "index filters by category" do
    allow_any_instance_of(TemplateRegistry).to receive(:categories).and_return([])
    expect_any_instance_of(TemplateRegistry).to receive(:by_category).with("databases").and_return([])

    get "/api/v1/templates", params: { category: "databases" }, headers: headers
    expect(response).to have_http_status(:success)
  end

  it "index filters by search query" do
    allow_any_instance_of(TemplateRegistry).to receive(:categories).and_return([])
    expect_any_instance_of(TemplateRegistry).to receive(:search).with("redis").and_return([])

    get "/api/v1/templates", params: { q: "redis" }, headers: headers
    expect(response).to have_http_status(:success)
  end

  it "show returns 404 when template missing" do
    allow_any_instance_of(TemplateRegistry).to receive(:find).and_return(nil)

    get "/api/v1/templates/nonexistent", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "show returns template json when found" do
    allow_any_instance_of(TemplateRegistry).to receive(:find).and_return({ slug: "uptime-kuma", name: "Uptime Kuma" })

    get "/api/v1/templates/uptime-kuma", headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["slug"]).to eq("uptime-kuma")
  end

  it "deploy returns 404 when template not found" do
    allow_any_instance_of(TemplateRegistry).to receive(:find).and_return(nil)

    post "/api/v1/templates/deploy",
      params: { slug: "nonexistent", server_id: server.id, app_name: "abc" },
      headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "deploy returns 422 when app_name is blank" do
    allow_any_instance_of(TemplateRegistry).to receive(:find).and_return({ slug: "n8n", name: "n8n" })

    post "/api/v1/templates/deploy",
      params: { slug: "n8n", server_id: server.id, app_name: "" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "deploy returns 409 when app name is already taken" do
    allow_any_instance_of(TemplateRegistry).to receive(:find).and_return({ slug: "n8n", name: "n8n" })
    existing = app_records(:one)

    post "/api/v1/templates/deploy",
      params: { slug: "n8n", server_id: server.id, app_name: existing.name },
      headers: headers
    expect(response).to have_http_status(:conflict)
  end

  it "deploy enqueues TemplateDeployJob and returns app+deploy" do
    allow_any_instance_of(TemplateRegistry).to receive(:find).and_return({ slug: "n8n", name: "n8n" })

    expect {
      post "/api/v1/templates/deploy",
        params: { slug: "n8n", server_id: server.id, app_name: "fresh-app" },
        headers: headers
    }.to have_enqueued_job(TemplateDeployJob)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["app"]["name"]).to eq("fresh-app")
    expect(body["deploy"]["id"]).to be_present
  end
end

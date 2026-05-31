# frozen_string_literal: true
require "rails_helper"

RSpec.describe "POST /vps_pain_lead", type: :request do
  let(:valid_params) { { lead: { email: "f@example.com", pain_text: "5 client VPSes" }, hp: "" } }
  let(:default_headers) { { "User-Agent" => "Mozilla/5.0 (RSpec Request Spec)" } }

  before { Rack::Attack.cache.store.clear if defined?(Rack::Attack) }

  it "creates a Lead and redirects with thanks" do
    expect {
      post "/vps_pain_lead", params: valid_params, headers: default_headers
    }.to change(Lead, :count).by(1)
    expect(response).to redirect_to("/vps_pain_lead/thanks")
    lead = Lead.last
    expect(lead.email).to eq("f@example.com")
    expect(lead.pain_text).to eq("5 client VPSes")
    expect(lead.channel).to eq("form")
    expect(lead.ip).to be_present
    expect(lead.user_agent).to be_present
  end

  it "silently redirects bots without creating a Lead (honeypot tripped)" do
    expect {
      post "/vps_pain_lead",
        params: { lead: { email: "bot@spam.com", pain_text: "buy now" }, hp: "filled" },
        headers: default_headers
    }.not_to change(Lead, :count)
    expect(response).to redirect_to("/vps_pain_lead/thanks")
  end

  it "emits vps_pain_lead via the real analytics bridge" do
    with_analytics_enabled do
      post "/vps_pain_lead", params: valid_params, headers: default_headers
      follow_redirect!
    end
    expect(response.body).to match(/posthog\.capture\("vps_pain_lead"/)
  end

  it "captures UTM from the session into the lead" do
    with_analytics_enabled do
      get "/?utm_source=meta&utm_medium=paid&utm_campaign=fvp-v1&utm_content=cr1&utm_term=id"
      post "/vps_pain_lead", params: valid_params
    end
    lead = Lead.last
    expect(lead.utm_source).to eq("meta")
    expect(lead.utm_campaign).to eq("fvp-v1")
    expect(lead.utm_content).to eq("cr1")
    expect(lead.utm_term).to eq("id")
  end

  it "renders the thanks page on GET" do
    get "/vps_pain_lead/thanks"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("thanks") # minimal — copy added in Task 6
  end

  it "rejects missing pain_text with re-render (no Lead created)" do
    expect {
      post "/vps_pain_lead", params: { lead: { email: "f@example.com", pain_text: "" }, hp: "" }, headers: default_headers
    }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "throttles to 5 POSTs per minute per IP" do
    Rack::Attack.enabled = true
    valid = { lead: { email: "f@example.com", pain_text: "x" }, hp: "" }
    5.times { post "/vps_pain_lead", params: valid, headers: default_headers }
    expect(response).to have_http_status(:redirect).or have_http_status(:ok)
    post "/vps_pain_lead", params: valid, headers: default_headers
    expect(response).to have_http_status(:too_many_requests)
  ensure
    Rack::Attack.enabled = false
  end
end

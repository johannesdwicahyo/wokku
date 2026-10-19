require "rails_helper"

RSpec.describe "Wake endpoint", type: :request do
  include ActiveJob::TestHelper
  let(:app) { create(:app_record, status: :sleeping) }
  let(:path) { "/__wake/#{app.wake_token}" }

  before { Rails.cache.clear }

  it "404s an invalid token" do
    get "/__wake/garbage"
    expect(response).to have_http_status(:not_found)
  end

  it "enqueues one wake for a burst of requests and answers a refreshing 503 page" do
    expect {
      3.times { get path, headers: { "Accept" => "text/html" } }
    }.to have_enqueued_job(WakeAppJob).with(app.id).exactly(:once)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("5")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include('http-equiv="refresh"', app.name)
  end

  it "answers plain text to API clients" do
    get path, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to eq("waking up, retry in 5s")
  end

  it "wakes on a webhook POST too (sender retries on 503)" do
    expect { post path, params: { a: 1 } }.to have_enqueued_job(WakeAppJob)
    expect(response).to have_http_status(:service_unavailable)
  end

  it "answers the waking page without enqueueing once the app is running" do
    app.update!(status: :running)
    expect { get path }.not_to have_enqueued_job(WakeAppJob)
    expect(response).to have_http_status(:service_unavailable)
  end

  it "404s a token for a deleted app" do
    token = app.wake_token
    app.destroy!
    get "/__wake/#{token}"
    expect(response).to have_http_status(:not_found)
  end
end

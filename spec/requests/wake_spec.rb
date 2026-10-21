require "rails_helper"

RSpec.describe "Wake endpoint", type: :request do
  include ActiveJob::TestHelper
  let(:sleeper) do
    create(:app_record, status: :sleeping).tap do |app|
      app.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: create(:dyno_tier, sleeps: true))
    end
  end
  let(:path) { "/__wake/#{sleeper.wake_token}" }

  # test env uses :null_store; the burst dedupe needs a real one
  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  it "404s an invalid token" do
    get "/__wake/garbage"
    expect(response).to have_http_status(:not_found)
  end

  it "enqueues one wake for a burst of requests and answers a refreshing 503 page" do
    expect {
      3.times { get path, headers: { "Accept" => "text/html" } }
    }.to have_enqueued_job(WakeAppJob).with(sleeper.id).exactly(:once)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("5")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include('http-equiv="refresh"', sleeper.name)
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
    sleeper.update!(status: :running)
    expect { get path }.not_to have_enqueued_job(WakeAppJob)
    expect(response).to have_http_status(:service_unavailable)
  end

  # A billing-suspended paid app also has status sleeping; an old token
  # (route not yet re-rendered) must not promise it is waking.
  it "answers a non-refreshing 'paused' page for a paid app, without enqueueing" do
    sleeper.dyno_allocations.first.update!(dyno_tier: create(:dyno_tier, sleeps: false))
    expect { get path, headers: { "Accept" => "text/html" } }.not_to have_enqueued_job(WakeAppJob)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include("paused", sleeper.name)
    expect(response.body).not_to include('http-equiv="refresh"')
    expect(response.body).not_to include("free app")
    get path, headers: { "Accept" => "application/json" }
    expect(response.body).to eq("app unavailable")
  end

  it "404s a token for a deleted app" do
    token = sleeper.wake_token
    sleeper.destroy!
    get "/__wake/#{token}"
    expect(response).to have_http_status(:not_found)
  end
end

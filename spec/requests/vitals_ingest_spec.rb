require "rails_helper"

RSpec.describe "POST /vitals/ingest", type: :request do
  let(:app_record) { app_records(:one) }
  before { app_record.ensure_vitals_ingest_token! }

  it "writes an event row for a valid token + metric" do
    expect {
      post "/vitals/ingest", params: { t: app_record.vitals_ingest_token, metric: "LCP", value: 1234.5 }
    }.to change(VitalsEvent, :count).by(1)
    expect(response).to have_http_status(:no_content)

    event = VitalsEvent.last
    expect(event.app_record_id).to eq(app_record.id)
    expect(event.metric).to eq("LCP")
    expect(event.value_ms).to eq(1234.5)
  end

  it "returns 404 for an unknown token" do
    expect {
      post "/vitals/ingest", params: { t: "nope", metric: "LCP", value: 100 }
    }.not_to change(VitalsEvent, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 422 for a bad metric" do
    expect {
      post "/vitals/ingest", params: { t: app_record.vitals_ingest_token, metric: "BOGUS", value: 100 }
    }.not_to change(VitalsEvent, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 422 for a negative value" do
    expect {
      post "/vitals/ingest", params: { t: app_record.vitals_ingest_token, metric: "LCP", value: -1 }
    }.not_to change(VitalsEvent, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  describe "throttling" do
    before do
      # Force MemoryStore cache for the throttle scope of this test.
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.enabled = true
    end
    after { Rack::Attack.enabled = false }

    it "returns 429 after the per-token limit is exceeded" do
      601.times do
        post "/vitals/ingest", params: { t: app_record.vitals_ingest_token, metric: "LCP", value: 1 }
      end
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end

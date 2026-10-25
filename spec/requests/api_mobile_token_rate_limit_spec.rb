require "rails_helper"

RSpec.describe "Mobile token rate limit", type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  it "blocks the 6th POST within a minute from one IP" do
    5.times do
      post "/api/v1/auth/mobile/token", params: {}, as: :json, env: { "REMOTE_ADDR" => "10.2.2.2" }
      expect(response).not_to have_http_status(:too_many_requests)
    end
    post "/api/v1/auth/mobile/token", params: {}, as: :json, env: { "REMOTE_ADDR" => "10.2.2.2" }
    expect(response).to have_http_status(:too_many_requests)
  end
end

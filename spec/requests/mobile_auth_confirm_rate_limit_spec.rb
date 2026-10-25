require "rails_helper"

RSpec.describe "Mobile auth confirm rate limit", type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  it "blocks the 11th POST within a minute from one IP" do
    10.times do
      post "/mobile/auth/confirm", env: { "REMOTE_ADDR" => "10.3.3.3" }
      expect(response).not_to have_http_status(:too_many_requests)
    end
    post "/mobile/auth/confirm", env: { "REMOTE_ADDR" => "10.3.3.3" }
    expect(response).to have_http_status(:too_many_requests)
  end
end

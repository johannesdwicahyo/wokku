# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack device throttles", type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    example.run
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  describe "device_code_mint/ip" do
    it "allows up to 10 mints per hour from the same IP" do
      10.times do
        post api_v1_auth_device_code_path, env: { "REMOTE_ADDR" => "10.10.0.1" }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    it "blocks the 11th mint within the hour" do
      10.times do
        post api_v1_auth_device_code_path, env: { "REMOTE_ADDR" => "10.10.0.2" }
      end

      post api_v1_auth_device_code_path, env: { "REMOTE_ADDR" => "10.10.0.2" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "device_token_poll/ip" do
    it "allows up to 30 polls per minute from the same IP" do
      30.times do
        post api_v1_auth_device_token_path, params: { device_code: "unknown" }, env: { "REMOTE_ADDR" => "10.10.0.3" }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    it "blocks the 31st poll within the minute" do
      30.times do
        post api_v1_auth_device_token_path, params: { device_code: "unknown" }, env: { "REMOTE_ADDR" => "10.10.0.4" }
      end

      post api_v1_auth_device_token_path, params: { device_code: "unknown" }, env: { "REMOTE_ADDR" => "10.10.0.4" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "leaves the generic api/ip throttle unaffected by the device throttles" do
    10.times do
      post api_v1_auth_device_code_path, env: { "REMOTE_ADDR" => "10.10.0.5" }
    end
    post api_v1_auth_device_code_path, env: { "REMOTE_ADDR" => "10.10.0.5" }
    expect(response).to have_http_status(:too_many_requests)

    get api_v1_meta_path, env: { "REMOTE_ADDR" => "10.10.0.5" }
    expect(response).to have_http_status(:ok)
  end
end

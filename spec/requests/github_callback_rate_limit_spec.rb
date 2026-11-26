# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub callback rate limit", type: :request do
  include Devise::Test::IntegrationHelpers

  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    example.run
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  it "blocks the 21st callback within 10 minutes from one IP" do
    20.times do
      get "/github/callback", params: { installation_id: "1" }, env: { "REMOTE_ADDR" => "10.20.0.1" }
      expect(response).not_to have_http_status(:too_many_requests)
    end
    get "/github/callback", params: { installation_id: "1" }, env: { "REMOTE_ADDR" => "10.20.0.1" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "blocks the 11th callback within 10 minutes for one user, across IPs" do
    sign_in users(:one)
    10.times do |i|
      get "/github/callback", params: { installation_id: "abc" }, env: { "REMOTE_ADDR" => "10.21.0.#{i + 1}" }
      expect(response).not_to have_http_status(:too_many_requests)
    end
    get "/github/callback", params: { installation_id: "abc" }, env: { "REMOTE_ADDR" => "10.21.0.99" }
    expect(response).to have_http_status(:too_many_requests)
  end
end

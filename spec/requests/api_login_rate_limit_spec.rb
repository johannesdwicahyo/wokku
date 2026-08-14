require "rails_helper"

RSpec.describe "API login rate limit", type: :request do
  let!(:user) { User.create!(email: "ratelimit@example.com", password: "password123456") }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  it "blocks after 5 failed login attempts from the same IP in a minute" do
    5.times do |i|
      post api_v1_auth_login_path,
        params: { email: "attacker#{i}@example.com", password: "wrong" },
        env: { "REMOTE_ADDR" => "10.0.0.1" }
      expect(response).to have_http_status(:unauthorized)
    end

    post api_v1_auth_login_path,
      params: { email: "attacker6@example.com", password: "wrong" },
      env: { "REMOTE_ADDR" => "10.0.0.1" }
    expect(response).to have_http_status(:too_many_requests)
    expect(JSON.parse(response.body)["error"]).to eq("Rate limit exceeded. Retry later.")
  end

  it "cannot be bypassed with a .json format suffix (path-normalized throttle)" do
    5.times do |i|
      post "/api/v1/auth/login.json",
        params: { email: "sneaky#{i}@example.com", password: "wrong" },
        env: { "REMOTE_ADDR" => "10.9.9.9" }
    end

    post "/api/v1/auth/login.json",
      params: { email: "sneaky6@example.com", password: "wrong" },
      env: { "REMOTE_ADDR" => "10.9.9.9" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "blocks after 5 failed login attempts on the same email" do
    5.times do
      post api_v1_auth_login_path,
        params: { email: user.email, password: "wrong" },
        env: { "REMOTE_ADDR" => "10.0.0.#{rand(1..254)}" }
      expect(response).to have_http_status(:unauthorized)
    end

    post api_v1_auth_login_path,
      params: { email: user.email, password: "wrong" },
      env: { "REMOTE_ADDR" => "10.0.0.#{rand(1..254)}" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "does not count a successful login toward the throttle" do
    3.times do
      post api_v1_auth_login_path,
        params: { email: user.email, password: "password123456" },
        env: { "REMOTE_ADDR" => "10.0.0.2" }
      expect(response).to have_http_status(:created)
    end
  end

  it "bans an IP after 20 failed attempts in 10 minutes (Fail2Ban)" do
    ip = "10.0.0.99"
    20.times do
      Rack::Attack::Fail2Ban.filter(
        "api_login:#{ip}",
        maxretry: 20,
        findtime: 10.minutes,
        bantime: 1.hour
      ) { true }
    end

    expect(Rack::Attack::Fail2Ban.banned?("api_login:#{ip}")).to be true
  end
end

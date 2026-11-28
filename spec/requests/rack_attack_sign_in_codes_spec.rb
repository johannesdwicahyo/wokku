# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email sign-in code throttles", type: :request do
  around do |ex|
    Wokku.configure { |c| c.email_sign_in = true }
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    ex.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.reset!
    Wokku.configure { |c| c.email_sign_in = nil }
  end

  def statuses(n, &blk) = Array.new(n) { |i| blk.call(i); response.status }

  it "allows 10 code requests per IP per 10 minutes" do
    s = statuses(11) { |i| post "/users/sign_in/code", params: { email: "ip#{i}@example.com" }, env: { "REMOTE_ADDR" => "10.30.0.1" } }
    expect(s.first(10)).not_to include(429)
    expect(s.last).to eq(429)
  end

  it "allows 3 code requests per email per 10 minutes, across IPs and case variants" do
    variants = [ "victim@example.com", "VICTIM@example.com", " Victim@Example.com ", "victim@EXAMPLE.com" ]
    s = statuses(4) { |i| post "/users/sign_in/code", params: { email: variants[i] }, env: { "REMOTE_ADDR" => "10.31.0.#{i}" } }
    expect(s.first(3)).not_to include(429)
    expect(s.last).to eq(429)
  end

  it "keys the per-email limit on the form body, so a different query email doesn't dodge it" do
    s = statuses(4) do |i|
      post "/users/sign_in/code?email=decoy#{i}%40example.com", params: { email: "split@example.com" }, env: { "REMOTE_ADDR" => "10.36.0.#{i}" }
    end
    expect(s.first(3)).not_to include(429)
    expect(s.last).to eq(429)
  end

  it "allows 10 code requests per email per IP per day, without locking the email out for other IPs" do
    t0 = Time.current.beginning_of_day + 1.hour
    post_from = ->(ip) { post "/users/sign_in/code", params: { email: "Daily-Req@example.com" }, env: { "REMOTE_ADDR" => ip } }
    s = []
    5.times do |w| # 2 per 11 minutes stays under the 3/10-min per-email limit
      travel_to(t0 + (w * 11).minutes) { s += statuses(2) { post_from.call("10.37.0.1") } }
    end
    expect(s).not_to include(429)
    travel_to(t0 + 60.minutes) do
      post_from.call("10.37.0.1")
      expect(response).to have_http_status(:too_many_requests)
      post_from.call("10.37.0.2")
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  it "counts resends against the pending email" do
    post "/users/sign_in/code", params: { email: "resend@example.com" }, env: { "REMOTE_ADDR" => "10.32.0.1" }
    s = statuses(3) { |i| post "/users/sign_in/code/resend", env: { "REMOTE_ADDR" => "10.32.1.#{i}" } }
    expect(s.first(2)).not_to include(429)
    expect(s.last).to eq(429)
  end

  it "allows 20 verifies per IP per 10 minutes" do
    s = statuses(21) { post "/users/sign_in/code/verify", params: { code: "000000" }, env: { "REMOTE_ADDR" => "10.33.0.1" } }
    expect(s.first(20)).not_to include(429)
    expect(s.last).to eq(429)
  end

  it "allows 10 verifies per pending email per 10 minutes, across IPs" do
    post "/users/sign_in/code", params: { email: "verify@example.com" }, env: { "REMOTE_ADDR" => "10.34.0.1" }
    s = statuses(11) { |i| post "/users/sign_in/code/verify", params: { code: "000000" }, env: { "REMOTE_ADDR" => "10.34.1.#{i}" } }
    expect(s.first(10)).not_to include(429)
    expect(s.last).to eq(429)
  end

  it "allows 30 verifies per pending email per day" do
    post "/users/sign_in/code", params: { email: "daily@example.com" }, env: { "REMOTE_ADDR" => "10.35.0.1" }
    s = []
    3.times do |w|
      travel_to(Time.current.beginning_of_day + 1.hour + (w * 11).minutes) do
        s += statuses(10) { |i| post "/users/sign_in/code/verify", params: { code: "000000" }, env: { "REMOTE_ADDR" => "10.35.#{w}.#{i}" } }
      end
    end
    expect(s).not_to include(429)
    travel_to(Time.current.beginning_of_day + 1.hour + 34.minutes) do
      post "/users/sign_in/code/verify", params: { code: "000000" }, env: { "REMOTE_ADDR" => "10.35.9.9" }
    end
    expect(response).to have_http_status(:too_many_requests)
  end

  describe "429 page" do
    def flood(headers = {})
      4.times { post "/users/sign_in/code", params: { email: "flood@example.com" }, headers: headers, env: { "REMOTE_ADDR" => "10.40.0.1" } }
    end

    it "renders a localized HTML page for the sign-in-code paths" do
      flood
      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.headers["Retry-After"]).to eq("600")
      expect(response.body).to include("Too many attempts. Try again later, or sign in another way.")
      expect(Nokogiri::HTML(response.body).at_css("a[href='/users/sign_in']")).to be_present
    end

    it "speaks Indonesian from the locale cookie or Accept-Language" do
      Rack::Attack.reset!
      flood("Accept-Language" => "id-ID,id;q=0.9")
      expect(response.body).to include("Terlalu banyak percobaan. Coba lagi nanti, atau masuk dengan cara lain.")
      Rack::Attack.reset!
      cookies[:locale] = "id"
      flood
      expect(response.body).to include("Terlalu banyak percobaan.")
    end

    it "keeps the JSON responder on every other path" do
      6.times { post "/users/sign_in", params: { user: { email: "x@example.com", password: "nope" } }, env: { "REMOTE_ADDR" => "10.41.0.1" } }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).to eq("error" => "Rate limit exceeded. Retry later.")
    end
  end
end

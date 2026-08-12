# frozen_string_literal: true

require "rails_helper"
require Wokku::Engine.root.join("app/middleware/maintenance_gate")

RSpec.describe MaintenanceGate do
  # Downstream app: a sentinel so we can tell pass-through from the 503 page.
  let(:downstream) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "OK" ] ] } }
  let(:gate)       { described_class.new(downstream) }

  def env_for(path: "/dashboard", warden: nil, accept_language: nil)
    e = { "PATH_INFO" => path }
    e["warden"] = warden if warden
    e["HTTP_ACCEPT_LANGUAGE"] = accept_language if accept_language
    e
  end

  around do |example|
    prev = ENV["MAINTENANCE_MODE"]
    example.run
    prev.nil? ? ENV.delete("MAINTENANCE_MODE") : ENV["MAINTENANCE_MODE"] = prev
  end

  context "when maintenance mode is off" do
    before { ENV.delete("MAINTENANCE_MODE") }

    it "passes the request straight through" do
      status, _headers, body = gate.call(env_for)
      expect(status).to eq(200)
      expect(body).to eq([ "OK" ])
    end
  end

  context "when maintenance mode is on" do
    before { ENV["MAINTENANCE_MODE"] = "true" }

    it "serves a 503 maintenance page for a normal request" do
      status, headers, body = gate.call(env_for(path: "/dashboard"))
      expect(status).to eq(503)
      expect(headers["Content-Type"]).to eq("text/html; charset=utf-8")
      expect(headers["Retry-After"]).to eq("3600")
      expect(headers["Cache-Control"]).to eq("no-store")
      expect(body.first).to include("We're upgrading.")
    end

    %w[1 true yes on TRUE On].each do |flag|
      it "treats #{flag.inspect} as enabled" do
        ENV["MAINTENANCE_MODE"] = flag
        status, = gate.call(env_for)
        expect(status).to eq(503)
      end
    end

    it "bypasses the /up health check" do
      status, = gate.call(env_for(path: "/up"))
      expect(status).to eq(200)
    end

    it "bypasses asset + devise sub-paths (prefix match)" do
      %w[/assets/application.css /users/sign_in /users/password/new].each do |p|
        status, = gate.call(env_for(path: p))
        expect(status).to eq(200), "expected #{p} to pass through"
      end
    end

    it "does NOT bypass a path that merely starts with an allowed token" do
      # /upgrade must not be allowed just because /up is
      status, = gate.call(env_for(path: "/upgrade"))
      expect(status).to eq(503)
    end

    it "lets a signed-in admin through" do
      admin  = instance_double("User", admin?: true)
      warden = instance_double("Warden::Proxy")
      allow(warden).to receive(:user).with(:user).and_return(admin)
      status, = gate.call(env_for(warden: warden))
      expect(status).to eq(200)
    end

    it "blocks a signed-in non-admin" do
      member = instance_double("User", admin?: false)
      warden = instance_double("Warden::Proxy")
      allow(warden).to receive(:user).with(:user).and_return(member)
      status, = gate.call(env_for(warden: warden))
      expect(status).to eq(503)
    end

    it "renders the Indonesian page for an id Accept-Language" do
      _s, _h, body = gate.call(env_for(accept_language: "id-ID,id;q=0.9"))
      expect(body.first).to include("Kami sedang upgrade.")
    end

    it "renders English otherwise" do
      _s, _h, body = gate.call(env_for(accept_language: "en-US"))
      expect(body.first).to include("We're upgrading.")
    end
  end
end

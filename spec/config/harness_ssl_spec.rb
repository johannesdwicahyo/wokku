require "rails_helper"

# Self-host production forces HTTPS for browsers (via Caddy), but the agent
# and installer talk to the control plane over loopback http on
# 127.0.0.1:3000. assume_ssl made EVERY request look https, so the URLs the
# control plane handed the agent (connect script, build archive) were
# https://127.0.0.1:3000 — every self-host deploy failed (2026-11-16 audit).
RSpec.describe "harness SSL policy" do
  let(:local) { WokkuHarness::LOCAL_CONTROL_REQUEST }

  def req(headers = {})
    ActionDispatch::Request.new(Rack::MockRequest.env_for("http://127.0.0.1:3000/api/v1/agent/archive", headers))
  end

  it "treats requests that did not come through Caddy as local (no redirect)" do
    expect(local.call(req)).to be(true)
  end

  it "redirects browser traffic Caddy forwarded over plain http" do
    expect(local.call(req("HTTP_X_FORWARDED_PROTO" => "http"))).to be(false)
  end

  it "keeps https for browser traffic Caddy forwarded over TLS" do
    expect(local.call(req("HTTP_X_FORWARDED_PROTO" => "https"))).to be(false)
    expect(req("HTTP_X_FORWARDED_PROTO" => "https").base_url).to start_with("https://")
  end

  it "builds plain-http URLs for the local agent" do
    expect(req.base_url).to eq("http://127.0.0.1:3000")
  end
end

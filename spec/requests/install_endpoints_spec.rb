require "rails_helper"

RSpec.describe "connect-a-server installer endpoints", type: :request do
  it "serves the install script with the control URL baked in" do
    get "/install/wokkud.sh"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("CONTROL_URL=\"${WOKKU_CONTROL_URL:-http://www.example.com}\"")
    expect(response.body).to include("docker swarm init")
    expect(response.body).to include("wokku-app-port-firewall") # blocks external app-port access
    expect(response.body).to include("PasswordAuthentication no")
    expect(response.body).to include("[Unit]") # systemd units embedded
  end

  # install.sh fetches this over loopback http, but force_ssl/assume_ssl
  # bakes https:// into request.base_url — the same-box install must be
  # able to override it (fresh installs broke 2026-08-08 → 11-16).
  it "lets WOKKU_CONTROL_URL override the baked-in control URL" do
    get "/install/wokkud.sh"
    line = response.body.lines.find { |l| l.start_with?("CONTROL_URL=") }
    run = ->(env) { IO.popen([ env, "bash", "-c", "#{line}\nprintf %s \"$CONTROL_URL\"" ], &:read) }
    expect(run.({ "WOKKU_CONTROL_URL" => "http://127.0.0.1:3000" })).to eq("http://127.0.0.1:3000")
    expect(run.({})).to eq("http://www.example.com")
  end

  # `docker info | grep -q` under pipefail exits 141 (SIGPIPE) even when the
  # swarm IS active, so a re-run (= upgrade) tried `swarm init` and died.
  it "detects an existing swarm without a grep -q pipeline" do
    get "/install/wokkud.sh"
    expect(response.body).to include("{{.Swarm.LocalNodeState}}")
    expect(response.body).not_to match(/\|\s*grep -q "Swarm/)
  end

  it "install.sh points the same-box agent at loopback http" do
    script = Wokku::Engine.root.join("install.sh").read
    expect(script).to include("WOKKU_CONTROL_URL=http://127.0.0.1:3000 bash -s")
  end

  # Shared-IP budget VPS: the provider's proxy also redirects http->https,
  # so only our app's health body proves the domain reaches this box.
  it "install.sh verifies public reachability by our /up body, not a redirect" do
    script = Wokku::Engine.root.join("install.sh").read
    expect(script).to include('curl -sk -m 4 "https://${DOMAIN}/up"')
    expect(script).to include("*green*")
    expect(script).to include("SHARES one public IP")
  end

  # Ubuntu's docker.io ships without buildx and nixpacks builds need it:
  # every source deploy on a fresh self-host failed (2026-11-16 audit).
  it "installs buildx when the host's docker lacks it" do
    get "/install/wokkud.sh"
    expect(response.body).to include("docker buildx version >/dev/null 2>&1 ||")
    expect(response.body).to include("docker-buildx")
  end

  it "404s the binary with a clear message when not bundled" do
    get "/install/wokkud"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("WOKKUD_BINARY_PATH")
  end
end

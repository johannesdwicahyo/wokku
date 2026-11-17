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

  # Small boxes (2 GB, no swap) risk OOM-killing npm/bundler builds.
  it "adds a 2 GB swap file only on small servers without swap" do
    get "/install/wokkud.sh"
    expect(response.body).to include("fallocate -l 2G /swapfile")
    expect(response.body).to match(/swapon --noheadings.*-lt 4096/m)
  end

  # The first nixpacks build downloads nixpkgs + the Node toolchain (~10 min
  # on a small box). A background throwaway Node 22 build (same package set
  # as the Node templates) primes Docker's layer cache, once per server.
  it "warms the build cache in the background once" do
    get "/install/wokkud.sh"
    body = response.body
    expect(body).to include("systemd-run --unit=wokku-build-warmup")
    expect(body).to include(%q("engines":{"node":"22"}))
    expect(body).to include("/var/lib/wokku/build-cache-warmed")
  end

  it "install.sh generates a setup token and prints the tokened setup link" do
    script = Wokku::Engine.root.join("install.sh").read
    expect(script).to include("WOKKU_SETUP_TOKEN=$(openssl rand -hex 16)")
    expect(script).to include("grep -q '^WOKKU_SETUP_TOKEN=' .env ||")
    expect(script).to include("/setup?token=${SETUP_TOKEN}")
  end

  # The 10 GB fresh-install minimum blocked updates on a 20 GB VPS.
  it "install.sh needs only 2 GB free to update, and drops the previous Wokku image" do
    script = Wokku::Engine.root.join("install.sh").read
    expect(script).to include('[ "$disk_gb" -ge 2 ]', '[ "$disk_gb" -ge 10 ]')
    expect(script).to include('docker image prune -f --filter "label=org.opencontainers.image.title=wokku"')
  end

  # `curl | sudo bash` feeds the script on stdin; a stdin-reading command
  # swallowed the rest of it and the install "succeeded" halfway (11-17).
  it "install.sh runs from a function so it survives being piped into bash" do
    lines = Wokku::Engine.root.join("install.sh").read.lines.map(&:strip).reject(&:empty?)
    expect(lines).to include("main() {")
    expect(lines.last).to eq('main "$@"')
  end

  it "404s the binary with a clear message when not bundled" do
    get "/install/wokkud"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("WOKKUD_BINARY_PATH")
  end
end

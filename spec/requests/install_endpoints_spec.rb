require "rails_helper"

RSpec.describe "connect-a-server installer endpoints", type: :request do
  it "serves the install script with the control URL baked in" do
    get "/install/wokkud.sh"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("CONTROL_URL=\"http://www.example.com\"")
    expect(response.body).to include("docker swarm init")
    expect(response.body).to include("wokku-app-port-firewall") # blocks external app-port access
    expect(response.body).to include("PasswordAuthentication no")
    expect(response.body).to include("[Unit]") # systemd units embedded
  end

  it "404s the binary with a clear message when not bundled" do
    get "/install/wokkud"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("WOKKUD_BINARY_PATH")
  end
end

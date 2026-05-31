require "rails_helper"
require Rails.root.join("app/middleware/maintenance_gate")

RSpec.describe MaintenanceGate do
  let(:inner_app) { ->(env) { [ 200, { "Content-Type" => "text/plain" }, [ "downstream" ] ] } }
  let(:gate)      { described_class.new(inner_app) }

  def request_env(path:, warden_user: nil, accept_language: "en")
    env = Rack::MockRequest.env_for(path, "HTTP_ACCEPT_LANGUAGE" => accept_language)
    if warden_user
      warden = instance_double("Warden::Proxy")
      allow(warden).to receive(:user).with(:user).and_return(warden_user)
      env["warden"] = warden
    end
    env
  end

  context "when MAINTENANCE_MODE is off" do
    before { ENV["MAINTENANCE_MODE"] = nil }

    it "passes everything through" do
      status, _h, body = gate.call(request_env(path: "/dashboard/apps"))
      expect(status).to eq(200)
      expect(body.first).to eq("downstream")
    end
  end

  context "when MAINTENANCE_MODE=true" do
    before { ENV["MAINTENANCE_MODE"] = "true" }
    after  { ENV["MAINTENANCE_MODE"] = nil }

    it "returns 503 with the maintenance page for anonymous users" do
      status, headers, body = gate.call(request_env(path: "/dashboard/apps"))
      expect(status).to eq(503)
      expect(headers["Content-Type"]).to start_with("text/html")
      expect(body.first).to include("We're upgrading")
      expect(body.first).to include("Apps you've already deployed")
    end

    it "returns Indonesian copy when Accept-Language starts with id" do
      _s, _h, body = gate.call(request_env(path: "/dashboard/apps", accept_language: "id-ID,id;q=0.9"))
      expect(body.first).to include("Kami sedang upgrade")
      expect(body.first).to include("App yang sudah ter-deploy")
    end

    it "passes /up healthcheck through" do
      status, _h, body = gate.call(request_env(path: "/up"))
      expect(status).to eq(200)
      expect(body.first).to eq("downstream")
    end

    it "passes /assets/* through" do
      status, _h, body = gate.call(request_env(path: "/assets/application-abc.css"))
      expect(status).to eq(200)
      expect(body.first).to eq("downstream")
    end

    it "passes Devise sign-in routes through" do
      status, _h, body = gate.call(request_env(path: "/users/sign_in"))
      expect(status).to eq(200)
      expect(body.first).to eq("downstream")
    end

    it "passes signed-in admin users through" do
      admin = double("User", admin?: true)
      status, _h, body = gate.call(request_env(path: "/dashboard/apps", warden_user: admin))
      expect(status).to eq(200)
      expect(body.first).to eq("downstream")
    end

    it "blocks signed-in non-admin users" do
      member = double("User", admin?: false)
      status, _h, _body = gate.call(request_env(path: "/dashboard/apps", warden_user: member))
      expect(status).to eq(503)
    end
  end
end

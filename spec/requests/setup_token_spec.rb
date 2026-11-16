require "rails_helper"

# Until the admin exists, whoever opens /setup first owned the install —
# and bots probe a new VPS within the hour (2026-11-16 audit). install.sh
# now writes WOKKU_SETUP_TOKEN and prints /setup?token=…; without a token
# configured, only same-machine / private-network visitors may set up.
RSpec.describe "setup token", type: :request do
  let(:admin_params) do
    { user: { email: "owner@selfhost.local", password: "a-strong-password-123", password_confirmation: "a-strong-password-123" } }
  end

  before do
    allow(User).to receive(:exists?).and_return(false)
    users(:admin).update_column(:role, 0)
    stub_const("User::ADMIN_EMAIL", "owner@selfhost.local")
  end

  around do |ex|
    orig = ENV["WOKKU_SETUP_TOKEN"]
    ex.run
  ensure
    orig ? ENV["WOKKU_SETUP_TOKEN"] = orig : ENV.delete("WOKKU_SETUP_TOKEN")
  end

  context "with WOKKU_SETUP_TOKEN set" do
    before { ENV["WOKKU_SETUP_TOKEN"] = "s3cr3t-token" }

    it "refuses /setup without the token and says where to find it" do
      get "/setup"
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("WOKKU_SETUP_TOKEN")
      expect(response.body).not_to include("s3cr3t-token")
    end

    it "refuses a wrong token" do
      get "/setup", params: { token: "guess" }
      expect(response).to have_http_status(:forbidden)
    end

    it "serves the form with the right token and carries it into the POST" do
      get "/setup", params: { token: "s3cr3t-token" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="token"').and include('value="s3cr3t-token"')
    end

    it "refuses to create the admin without the token" do
      expect { post "/setup", params: admin_params }.not_to change(User, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "creates the admin with the token" do
      post "/setup", params: admin_params.merge(token: "s3cr3t-token")
      expect(response).to redirect_to("/dashboard")
      expect(User.find_by(email: "owner@selfhost.local")&.role).to eq("admin")
    end
  end

  context "without a token configured" do
    before { ENV.delete("WOKKU_SETUP_TOKEN") }

    it "allows setup from this machine or a private network (docker compose locally)" do
      get "/setup", headers: { "REMOTE_ADDR" => "172.18.0.1" }
      expect(response).to have_http_status(:ok)
    end

    it "refuses a visitor from the public internet" do
      get "/setup", env: { "REMOTE_ADDR" => "203.0.113.9" }
      expect(response).to have_http_status(:forbidden)
    end
  end
end

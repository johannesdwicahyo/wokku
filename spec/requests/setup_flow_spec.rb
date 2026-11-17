require "rails_helper"

# First-boot setup: zero users → /setup creates the single admin
# (engine rule is count-based; the cloud pins the admin email via
# config/initializers/wokku_cloud_admin.rb on top).
RSpec.describe "first-boot setup", type: :request do
  it "redirects everything to /setup when no users exist, and /setup away when they do" do
    allow(User).to receive(:exists?).and_return(false)
    get "/users/sign_in"
    expect(response).to redirect_to("/setup")

    allow(User).to receive(:exists?).and_return(true)
    get "/setup"
    expect(response).to redirect_to("/users/sign_in")
  end

  it "creates the admin, signs in, and redirects to the dashboard" do
    allow(User).to receive(:exists?).and_return(false)
    users(:admin).update_column(:role, 0) # engine count-rule sees no other admin
    stub_const("User::ADMIN_EMAIL", "owner@selfhost.local") # cloud email-pin follows the setup email here

    post "/setup", params: { user: { email: "owner@selfhost.local",
                                     password: "a-strong-password-123",
                                     password_confirmation: "a-strong-password-123" } }
    expect(response).to redirect_to("/dashboard")
    created = User.find_by(email: "owner@selfhost.local")
    expect(created.role).to eq("admin")
    expect(created.personal_team).to be_present
  end

  # The setup page follows the visitor's language (cookie / browser); the
  # admin must keep it after sign-in instead of dropping to the 'en' default.
  it "keeps the language the admin set up in" do
    allow(User).to receive(:exists?).and_return(false)
    users(:admin).update_column(:role, 0)
    stub_const("User::ADMIN_EMAIL", "owner@selfhost.local")

    post "/setup", params: { user: { email: "owner@selfhost.local",
                                     password: "a-strong-password-123",
                                     password_confirmation: "a-strong-password-123" } },
                   headers: { "HTTP_ACCEPT_LANGUAGE" => "id-ID,id;q=0.9" }
    expect(User.find_by(email: "owner@selfhost.local").locale).to eq("id")
  end

  it "pre-registers this host as the first server when the checkbox is on" do
    allow(User).to receive(:exists?).and_return(false)
    users(:admin).update_column(:role, 0)
    stub_const("User::ADMIN_EMAIL", "owner@selfhost.local")

    post "/setup", params: { connect_this_server: "1",
                             user: { email: "owner@selfhost.local",
                                     password: "a-strong-password-123",
                                     password_confirmation: "a-strong-password-123" } }
    server = Server.find_by(name: "main")
    expect(server).to be_present
    expect(server.host).to eq("www.example.com") # request.host in request specs
    expect(response).to redirect_to("/admin/servers/#{server.id}")
  end

  it "re-renders with errors on bad input" do
    allow(User).to receive(:exists?).and_return(false)
    post "/setup", params: { user: { email: "bad", password: "x", password_confirmation: "y" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

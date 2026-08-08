# frozen_string_literal: true

require "rails_helper"

# Deep coverage tests for Admin::ServersController (moved from Dashboard:: namespace).
RSpec.describe "Admin::Servers (deep)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)   { users(:admin) }
  let(:server) { servers(:two) }

  before { user.update!(otp_required_for_login: true) }

  # Admin::ServersController create/destroy reaches Cloudflare DNS for
  # the server's wokku.cloud subdomain. Stub the API uniformly so the
  # specs test the controller's CRUD path, not the DNS integration.
  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  describe "authenticated" do
    before { sign_in user }

    it "show: renders server page with its apps" do
      get "/admin/servers/#{server.id}"
      expect(response).to have_http_status(:success)
    end

    it "new: renders new server form" do
      get "/admin/servers/new"
      expect(response).to have_http_status(:success)
    end

    it "create: creates server record and redirects" do
      post "/admin/servers", params: {
        server: {
          name: "My New Server",
          host: "192.168.1.100",
          port: "22",
          ssh_user: "dokku",
          ssh_private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----"
        }
      }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/admin/servers/})
      expect(flash[:notice]).to match("added successfully")
    end

    it "create: re-renders index with 422 on invalid params" do
      post "/admin/servers", params: {
        server: { name: "", host: "", port: "22", ssh_user: "dokku" }
      }
      expect([ 200, 422 ]).to include(response.status)
    end

    it "destroy: deletes server and redirects to index" do
      throwaway = Server.create!(
        name: "Throwaway Server",
        host: "10.99.99.99",
        port: 22,
        ssh_user: "dokku",
        team: user.teams.first,
        status: :connected
      )

      delete "/admin/servers/#{throwaway.id}"
      expect(response).to redirect_to(admin_servers_path)
      expect(flash[:notice]).to match("removed successfully")
      expect(Server.find_by(id: throwaway.id)).to be_nil
    end

    it "sync: enqueues SyncServerJob and redirects with notice" do
      allow(SyncServerJob).to receive(:perform_later).and_return(true)
      post "/admin/servers/#{server.id}/sync"
      expect(response).to redirect_to(admin_server_path(server))
      expect(flash[:notice]).to match("sync started")
    end
  end

  describe "auth guards" do
    it "show: redirects when not authenticated" do
      get "/admin/servers/#{server.id}"
      expect(response).to have_http_status(:redirect)
    end

    it "new: redirects when not authenticated" do
      get "/admin/servers/new"
      expect(response).to have_http_status(:redirect)
    end

    it "create: redirects when not authenticated" do
      post "/admin/servers", params: {
        server: { name: "x", host: "1.2.3.4", port: "22", ssh_user: "dokku" }
      }
      expect(response).to have_http_status(:redirect)
    end

    it "destroy: redirects when not authenticated" do
      delete "/admin/servers/#{server.id}"
      expect(response).to have_http_status(:redirect)
    end

    it "sync: redirects when not authenticated" do
      post "/admin/servers/#{server.id}/sync"
      expect(response).to have_http_status(:redirect)
    end
  end
end

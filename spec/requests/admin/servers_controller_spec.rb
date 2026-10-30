# frozen_string_literal: true

require "rails_helper"

# Admin::ServersController create/destroy route through
# Wokku.config.dns_provider (create on add, delete on destroy).
# Which zone(s) that provider actually writes to is Cloudflare::DnsProvider's
# job — see spec/services/cloudflare/dns_provider_spec.rb.
RSpec.describe "Admin::Servers — DNS provider calls", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { users(:admin) }
  let(:dns) { Wokku.config.dns_provider }

  before do
    sign_in admin
    allow(dns).to receive(:create_app_record)
    allow(dns).to receive(:delete_app_record)
  end

  describe "POST create" do
    it "creates the server's DNS record via the configured dns_provider" do
      post admin_servers_path, params: { server: { name: "zone-off-srv", host: "5.5.5.5", port: 22, ssh_user: "dokku" } }
      expect(dns).to have_received(:create_app_record).with("zone-off-srv", "5.5.5.5")
    end
  end

  describe "DELETE destroy" do
    it "cleans up the server's DNS record via the configured dns_provider" do
      server = Server.create!(name: "doomed-srv", host: "7.7.7.7", port: 22, ssh_user: "dokku")
      delete admin_server_path(server)
      expect(dns).to have_received(:delete_app_record).with("doomed-srv")
    end
  end
end

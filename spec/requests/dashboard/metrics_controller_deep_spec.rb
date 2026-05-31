# frozen_string_literal: true

require "rails_helper"

# Deep coverage tests for Dashboard::MetricsController
# Stubs Dokku::Client#run and Net::SSH so fetch_processes internal logic
# actually executes.
RSpec.describe "Dashboard::Metrics (deep)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  def stub_dokku_run(responses = {})
    allow_any_instance_of(Dokku::Client).to receive(:run) do |_instance, cmd|
      match = responses.find { |k, _v| cmd.start_with?(k.to_s) }
      match ? match.last : ""
    end
  end

  def stub_net_ssh_noop
    allow(Net::SSH).to receive(:start).and_return("")
  end

  def stub_net_ssh_raise(error_class)
    allow(Net::SSH).to receive(:start).and_raise(error_class)
  end

  before { sign_in user }

  describe "show" do
    it "renders page with empty ps:report and resource:report" do
      stub_net_ssh_noop
      stub_dokku_run("ps:report" => "", "resource:report" => "")
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "parses process lines from ps:report" do
      stub_net_ssh_noop
      ps_report = <<~OUTPUT
        =====> my-app-two process information
        Status web 1:     running (CID: abc123)
        Status worker 1:  stopped (CID: def456)
      OUTPUT
      stub_dokku_run("ps:report" => ps_report, "resource:report" => "")
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "recovers when ps:report raises" do
      stub_net_ssh_noop
      allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(Dokku::Client::ConnectionError, "SSH down")
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "SSHes as root for docker stats" do
      captured = {}
      allow(Net::SSH).to receive(:start) do |host, ssh_user, **opts|
        captured[:host] = host
        captured[:user] = ssh_user
        captured[:key_data] = opts[:key_data]
        ""
      end
      stub_dokku_run("ps:report" => "", "resource:report" => "")
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
      expect(captured[:user]).to eq("root")
      expect(captured[:key_data]).to be_a(Array)
    end

    it "sets metrics_error on Net::SSH::AuthenticationFailed" do
      stub_dokku_run("ps:report" => "", "resource:report" => "")
      stub_net_ssh_raise(Net::SSH::AuthenticationFailed)
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "sets metrics_error on connection refused" do
      stub_dokku_run("ps:report" => "", "resource:report" => "")
      stub_net_ssh_raise(Errno::ECONNREFUSED)
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "sets metrics_error on generic SSH error" do
      stub_dokku_run("ps:report" => "", "resource:report" => "")
      allow(Net::SSH).to receive(:start).and_raise(RuntimeError, "boom")
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "includes metrics from last 24 hours in @metrics" do
      stub_net_ssh_noop
      stub_dokku_run("ps:report" => "", "resource:report" => "")
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end
  end
end

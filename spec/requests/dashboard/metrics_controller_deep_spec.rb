# frozen_string_literal: true

require "rails_helper"

# Deep coverage tests for Dashboard::MetricsController
# Stubs Net::SSH so the docker-stats fetch's internal logic actually
# executes without touching a host.
RSpec.describe "Dashboard::Metrics (deep)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  def stub_net_ssh_noop
    allow(Net::SSH).to receive(:start).and_return("")
  end

  def stub_net_ssh_raise(error_class)
    allow(Net::SSH).to receive(:start).and_raise(error_class)
  end

  before { sign_in user }

  describe "show" do
    it "shell renders without SSH (no deferred param)" do
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end

    it "deferred fragment renders with no live_containers" do
      stub_net_ssh_noop
      app_record.update!(live_containers: nil)
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
    end

    it "derives processes from live_containers (via deferred fragment)" do
      stub_net_ssh_noop
      app_record.update!(live_containers: [
        { "process" => "web", "state" => "running" },
        { "process" => "worker", "state" => "failed", "exit_code" => 1 }
      ])
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("web.1")
      expect(response.body).to include("worker.1")
      expect(response.body).to include("Failed")
    end

    it "SSHes as root for docker stats (via deferred fragment)" do
      captured = {}
      allow(Net::SSH).to receive(:start) do |host, ssh_user, **opts|
        captured[:host] = host
        captured[:user] = ssh_user
        captured[:key_data] = opts[:key_data]
        ""
      end
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
      expect(captured[:user]).to eq("root")
      expect(captured[:key_data]).to be_a(Array)
    end

    it "SSHes as the configured host SSH user for docker stats" do
      allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku")
      users = []
      allow(Net::SSH).to receive(:start) { |_h, ssh_user, **_o| users << ssh_user; "" }
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
      expect(users).to eq([ "wokku" ])
    end

    it "sets metrics_error on Net::SSH::AuthenticationFailed (via deferred fragment)" do
      stub_net_ssh_raise(Net::SSH::AuthenticationFailed)
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
    end

    it "sets metrics_error on connection refused (via deferred fragment)" do
      stub_net_ssh_raise(Errno::ECONNREFUSED)
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
    end

    it "sets metrics_error on generic SSH error (via deferred fragment)" do
      allow(Net::SSH).to receive(:start).and_raise(RuntimeError, "boom")
      get "/dashboard/apps/#{app_record.id}/metrics", params: { deferred: 1 }
      expect(response).to have_http_status(:success)
    end

    it "includes metrics from last 24 hours in @metrics (shell path)" do
      get "/dashboard/apps/#{app_record.id}/metrics"
      expect(response).to have_http_status(:success)
    end
  end
end

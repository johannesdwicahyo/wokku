# frozen_string_literal: true

require "rails_helper"

# B6 W2: native apps are born without a dokku shell — every dokku-touching
# job leg must skip or fail typed, never fall back.
RSpec.describe "wokkud-native guards" do
  let(:server) { create(:server) }

  describe AppRecord, "#runtime_env" do
    it "reads EnvVar rows for native apps, never dokku" do
      app = create(:app_record, server: server, wokkud_native: true)
      app.env_vars.create!(key: "FOO", value: "bar")
      expect(Hosts::Ssh).not_to receive(:new)

      expect(app.runtime_env).to eq("FOO" => "bar")
    end

    it "reads EnvVar rows for non-native apps too — cp_env_truth flipped 2026-07-19" do
      app = create(:app_record, server: server)
      app.env_vars.create!(key: "FOO", value: "cp")
      expect(Hosts::Ssh).not_to receive(:new)

      expect(app.runtime_env).to eq("FOO" => "cp")
    end
  end

  describe TarballDeployJob do
    it "fails the deploy instead of falling back to dokku when the builder is unavailable" do
      app = create(:app_record, server: server, wokkud_native: true)
      server.update!(wokkud_builds_enabled: false)
      deploy = create(:deploy, app_record: app, archive_key: "a/b.tar")

      described_class.perform_now(app_id: app.id, deploy_id: deploy.id)

      expect(deploy.reload.status).to eq("failed")
      expect(deploy.log).to include("builder unavailable")
      expect(app.reload.status).to eq("created")
    end
  end

  describe PostDeploySetupJob do
    it "runs only control-plane legs for native apps — no dokku client at all" do
      app = create(:app_record, server: server, wokkud_native: true)
      expect(Hosts::Ssh).not_to receive(:new)
      allow(Wokku.config.dns_provider).to receive(:create_app_record)

      described_class.perform_now(app.id)

      expect(app.releases.count).to eq(1)
    end
  end

  describe Lifecycle::Ops, ".converge! env" do
    it "assembles env from EnvVar rows for native apps" do
      app = create(:app_record, server: server, wokkud_native: true, wokkud_lifecycle: true, container_port: 5000)
      app.env_vars.create!(key: "SECRET", value: "s3cr3t")
      create(:deploy, :succeeded, :wokkud, app_record: app, formation_json: {})
      app.process_scales.create!(process_type: "web", count: 1)
      expect(Hosts::Ssh).not_to receive(:new)

      op = Lifecycle::Ops.converge!(app, wait: false)

      expect(op.params["env"]).to eq("SECRET" => "s3cr3t", "PORT" => "5000")
    end
  end

  describe "creation flag switch" do
    it "native_creates? is ON — every standard create births dokku-free (flipped 2026-07-19)" do
      expect(AppRecord.native_creates?).to be true
    end
  end
end

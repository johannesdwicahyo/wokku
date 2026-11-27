# frozen_string_literal: true

require "rails_helper"

RSpec.describe TarballDeployJob, type: :job do
  let(:app) { create(:app_record) }
  let(:deploy) { create(:deploy, app_record: app, archive_key: "deploy-archives/#{app.id}/#{SecureRandom.uuid}.tar.gz") }
  let(:store) { instance_double(Wokku::Providers::LocalBackupStore) }
  let(:base_args) { { app_id: app.id, deploy_id: deploy.id } }

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
    allow(Wokku.config).to receive(:backup_store).and_return(store)
    allow(store).to receive(:presigned_get).and_return("https://r2.example.com/signed-get-url")
    allow(PostDeploySetupJob).to receive(:perform_later)
  end

  # Every deploy now builds through wokkud (the dokku fallback is gone) —
  # arrange a wokkud-ready server and an already-claimed+finished build so
  # the generic-tail examples get straight past BuildAndConverge.
  def arrange_wokkud_build!(log: "archive extracted\n")
    app.server.update!(wokkud_builds_enabled: true)
    app.server.update_columns(heartbeat_at: Time.current, heartbeat_status: "ok", vitals: { "registry" => "ok" })
    deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current, log: log)
    allow(Lifecycle::Ops).to receive(:converge!)
  end

  it "can be enqueued" do
    expect { described_class.perform_later(**base_args) }.to have_enqueued_job(described_class)
  end

  describe "success path" do
    before do
      arrange_wokkud_build!
      allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return("")
    end

    it "marks the deploy succeeded, records the wokkud build tag as image_ref, and marks the app running" do
      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("succeeded")
      expect(deploy.image_ref).to eq(deploy.wokkud_image_ref)
      expect(app.reload.status).to eq("running")
    end

    it "streams the build log onto the deploy" do
      described_class.perform_now(**base_args)
      expect(deploy.reload.log).to include("archive extracted")
    end

    it "enqueues PostDeploySetupJob after success" do
      described_class.perform_now(**base_args)
      expect(PostDeploySetupJob).to have_received(:perform_later).with(app.id)
    end
  end

  describe "registry.prune op (agent-side, digest-aware)" do
    it "issues registry.prune for wokku/<app>, keeping the newest 5 image-ref'd deploys' tag suffixes" do
      old_deploys = (1..4).map do |days_ago|
        d = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: days_ago.days.ago)
        d.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{d.id}")
        d
      end
      # Older than the newest-5 window — must NOT be in keep_tags.
      too_old = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: 30.days.ago)
      too_old.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{too_old.id}")

      arrange_wokkud_build!
      expect(Lifecycle::Ops).to receive(:issue!)
        .with(have_attributes(id: app.id), "registry.prune",
              { "repo" => "wokku/#{app.name}", "keep_tags" => ([ deploy.id ] + old_deploys.map(&:id)).map(&:to_s) },
              wait: false, timeout: anything)

      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("succeeded")
    end

    it "does not fail the deploy when the prune op-issue itself errors" do
      arrange_wokkud_build!
      allow(Lifecycle::Ops).to receive(:issue!).and_raise(StandardError, "op dispatch failed")

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("succeeded")
      expect(app.reload.status).to eq("running")
    end

    it "fires deploy_succeeded (not deploy_failed) and still enqueues PostDeploySetupJob even when the prune op fails" do
      arrange_wokkud_build!
      allow(Lifecycle::Ops).to receive(:issue!).and_raise(StandardError, "op dispatch failed")
      fired_events = []
      allow_any_instance_of(described_class).to receive(:fire_notifications) do |_instance, _team, event, _deploy|
        fired_events << event
      end

      described_class.perform_now(**base_args)

      expect(fired_events).to eq([ "deploy_succeeded" ])
      expect(PostDeploySetupJob).to have_received(:perform_later).with(app.id)
    end
  end

  describe "terminal-status re-entry guard" do
    let(:deploy) do
      create(:deploy, app_record: app, status: :succeeded,
             archive_key: "deploy-archives/#{app.id}/#{SecureRandom.uuid}.tar.gz")
    end

    it "no-ops on a retry against an already-terminal deploy — no client calls, no re-deploy" do
      expect(Wokku.config).not_to receive(:backup_store)
      expect_any_instance_of(Hosts::Ssh).not_to receive(:run_raw_streaming)
      expect_any_instance_of(Hosts::Ssh).not_to receive(:run_raw)

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("succeeded")
    end
  end

  describe "failure handling" do
    it "marks deploy as failed on BuildAndConverge::Error" do
      allow(Deploys::BuildAndConverge).to receive(:call)
        .and_raise(Deploys::BuildAndConverge::Error, "wokkud build failed: boom")
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("failed")
      expect(app.reload.status).to eq("created")
      expect(deploy.reload.log).to include("wokkud build failed: boom")
    end

    it "marks deploy as timed_out on Timeout::Error" do
      allow(Deploys::BuildAndConverge).to receive(:call).and_raise(Timeout::Error, "deploy timed out")
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("timed_out")
      expect(app.reload.status).to eq("created")
      expect(deploy.reload.log).to include("timed out")
    end

    it "marks deploy as failed on Lifecycle::Ops::Busy (a restart/scale/wake racing this deploy), with the retry-shortly message in the log" do
      allow(Deploys::BuildAndConverge).to receive(:call).and_raise(Lifecycle::Ops::Busy.new(app))
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("failed")
      expect(app.reload.status).to eq("created")
      expect(deploy.reload.log).to include("another operation is in flight for #{app.name} — retry shortly")
    end
  end

  describe "run_after_deploy (B6 Task 7: post_deploy via stack.run)" do
    it "runs run_after_deploy after a successful build and succeeds the deploy" do
      deploy.update!(run_after_deploy: "bin/rails db:migrate")
      allow(Deploys::BuildAndConverge).to receive(:call).and_return("log")
      expect(::Lifecycle::Ops).to receive(:run!).with(app, "bin/rails db:migrate", deploy: deploy)

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("succeeded")
    end

    it "fails the deploy with the command output when post_deploy exits nonzero" do
      deploy.update!(run_after_deploy: "bin/rails db:migrate")
      allow(Deploys::BuildAndConverge).to receive(:call).and_return("log")
      failed_op = build(:lifecycle_op, kind: "stack.run", status: :failed,
                        error: "command exited 7", error_code: "command_failed",
                        result: { "exit_code" => 7, "output" => "PG::UndefinedTable" })
      allow(::Lifecycle::Ops).to receive(:run!).and_raise(::Lifecycle::Ops::Failed.new(failed_op))

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("failed")
      expect(deploy.log).to include("PG::UndefinedTable")
    end

    it "fails the deploy but keeps the app running when Swarm rolled the new version back" do
      arrange_wokkud_build!
      rolled = build(:lifecycle_op, kind: "stack.converge", status: :failed,
                     error: "new version did not start", error_code: "rollout_failed")
      allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Failed.new(rolled))
      app.update!(status: :running)

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("failed")
      expect(deploy.log).to include("previous version is still running")
      expect(app.reload.status).to eq("running")
    end

    it "does not issue a run when run_after_deploy is blank" do
      allow(Deploys::BuildAndConverge).to receive(:call).and_return("log")
      expect(::Lifecycle::Ops).not_to receive(:run!)

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("succeeded")
    end
  end

  describe "wokkud build path (Phase 4c)" do
    before do
      app.server.update!(wokkud_builds_enabled: true)
      app.server.update_columns(heartbeat_at: Time.current, heartbeat_status: "ok", vitals: { "registry" => "ok" })
      allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return("")
    end

    it "waits for the wokkud build, then converges the image and keeps the streamed build log" do
      # Simulate an agent that already claimed + finished (job's polls
      # return true on first check — no sleeps in the spec).
      deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current,
                     log: "streamed build output\n")
      expect(Lifecycle::Ops).to receive(:converge!)
        .with(have_attributes(id: app.id), image_ref: deploy.wokkud_image_ref, deploy: deploy)
      expect(Hosts::Ssh).not_to receive(:new)

      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("succeeded")
      expect(deploy.log).to include("streamed build output")
      expect(app.reload.status).to eq("running")
      expect(PostDeploySetupJob).to have_received(:perform_later).with(app.id)
    end

    it "fails the deploy with the wokkud error when the build fails — no fallback, streamed log preserved" do
      deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current,
                     build_error: "nixpacks: exit 1", log: "streamed build output\n")
      expect(Hosts::Ssh).not_to receive(:new)

      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("failed")
      expect(deploy.log).to include("streamed build output").and include("nixpacks: exit 1")
      expect(app.reload.status).to eq("created")
    end

    it "fails the deploy when nobody claims within CLAIM_WAIT — no dokku fallback" do
      stub_const("Deploys::BuildAndConverge::CLAIM_WAIT", 0)
      expect(Hosts::Ssh).not_to receive(:new)

      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("failed")
      expect(deploy.log).to include("did not pick up the build")
      expect(app.reload.status).to eq("created")
    end

    it "fails the deploy when the heartbeat is stale — builder unavailable, no dokku fallback" do
      app.server.update_columns(heartbeat_at: 5.minutes.ago)

      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("failed")
      expect(deploy.log).to include("builder unavailable")
      expect(app.reload.status).to eq("created")
    end

    it "fails the deploy when the registry is unreachable — builder unavailable, no dokku fallback" do
      app.server.update_columns(vitals: { "registry" => "unreachable" })

      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("failed")
      expect(deploy.log).to include("builder unavailable")
      expect(app.reload.status).to eq("created")
    end
  end
end

RSpec.describe TarballDeployJob, "image scan hook", type: :job do
  let(:app) { create(:app_record) }
  let(:deploy) { create(:deploy, app_record: app, archive_key: "deploy-archives/#{app.id}/x.tar.gz") }

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
    allow(Wokku.config).to receive(:backup_store).and_return(instance_double(Wokku::Providers::LocalBackupStore, presigned_get: "https://x"))
    allow(PostDeploySetupJob).to receive(:perform_later)
    app.server.update!(wokkud_builds_enabled: true)
    app.server.update_columns(heartbeat_at: Time.current, heartbeat_status: "ok", vitals: { "registry" => "ok" })
    deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current)
    allow(Lifecycle::Ops).to receive(:converge!)
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return("")
  end

  it "queues a pending scan with the deploy's recorded image_ref" do
    allow(Wokku.config).to receive(:image_scans?).and_return(true)
    described_class.perform_now(app_id: app.id, deploy_id: deploy.id)
    deploy.reload
    expect(deploy.image_ref).to be_present
    expect(ImageScan.pending.count).to eq(1)
    expect(ImageScan.pending.first.image_ref).to eq(deploy.image_ref)
  end

  it "does not fail the deploy if the scan enqueue is broken" do
    allow(Wokku.config).to receive(:image_scans?).and_return(true)
    allow(ImageScan).to receive(:create!).and_raise("boom")
    expect(Rails.logger).to receive(:warn).with(/Enqueue/).at_least(:once)
    described_class.perform_now(app_id: app.id, deploy_id: deploy.id)
    expect(deploy.reload.status).to eq("succeeded")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe RollbackDeployJob, type: :job do
  let(:app) { create(:app_record) }
  let(:base_args) { { app_id: app.id, deploy_id: deploy.id } }

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
    allow(PostDeploySetupJob).to receive(:perform_later)
  end

  it "can be enqueued" do
    deploy = create(:deploy, app_record: app, image_ref: "127.0.0.1:5000/wokku/#{app.name}:some-id")
    expect { described_class.perform_later(app_id: app.id, deploy_id: deploy.id) }.to have_enqueued_job(described_class)
  end

  describe "image_ref path (fast — no rebuild)" do
    let(:target_tag) { "127.0.0.1:5000/wokku/#{app.name}:11111111-1111-1111-1111-111111111111" }
    let(:deploy) { create(:deploy, app_record: app, image_ref: target_tag) }

    before { allow(Lifecycle::Ops).to receive(:converge!) }

    it "rolls back by converging the reused image_ref via wokkud" do
      expect(Lifecycle::Ops).to receive(:converge!)
        .with(have_attributes(id: app.id), image_ref: target_tag, deploy: deploy)
      described_class.perform_now(**base_args)
    end

    it "marks the deploy succeeded and the app running" do
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("succeeded")
      expect(app.reload.status).to eq("running")
    end

    it "keeps image_ref exactly as the reused tag — does not re-tag under its own deploy id" do
      described_class.perform_now(**base_args)
      expect(deploy.reload.image_ref).to eq(target_tag)
    end

    it "logs that the rollback reused the already-built image" do
      described_class.perform_now(**base_args)
      expect(deploy.reload.log).to include(target_tag).and include("via wokkud")
    end

    it "enqueues PostDeploySetupJob and fires deploy_succeeded" do
      fired_events = []
      allow_any_instance_of(described_class).to receive(:fire_notifications) do |_i, _team, event, _deploy|
        fired_events << event
      end
      described_class.perform_now(**base_args)
      expect(PostDeploySetupJob).to have_received(:perform_later).with(app.id)
      expect(fired_events).to eq([ "deploy_succeeded" ])
    end
  end

  describe "archive_key path (slower — rebuild via Deploys::BuildAndConverge)" do
    let(:archive_key) { "deploy-archives/#{app.id}/#{SecureRandom.uuid}.tar.gz" }
    let(:deploy) { create(:deploy, app_record: app, archive_key: archive_key) }

    before { allow(Deploys::BuildAndConverge).to receive(:call).and_return("archive rebuilt\n") }

    it "rebuilds via Deploys::BuildAndConverge for this app/deploy" do
      expect(Deploys::BuildAndConverge).to receive(:call).with(app: app, deploy: deploy)
      described_class.perform_now(**base_args)
    end

    it "logs that this path is slower than an image-based rollback" do
      broadcasts = []
      allow(DeployChannel).to receive(:broadcast_to) { |_d, payload| broadcasts << payload }
      described_class.perform_now(**base_args)
      expect(broadcasts.map { |p| p[:data] }.join).to include("slower")
    end

    it "marks the deploy succeeded with the rebuild log, and records the rollback artifact" do
      described_class.perform_now(**base_args)
      deploy.reload
      expect(deploy.status).to eq("succeeded")
      expect(deploy.log).to include("archive rebuilt")
      expect(app.reload.status).to eq("running")
    end

    it "records the rollback artifact (image_ref pointed at the wokkud build tag) after a wokkud rebuild" do
      # The job's `deploy` is its own Deploy.find(deploy_id) instance, not this
      # example's `let(:deploy)` — mutate the one BuildAndConverge is actually
      # called with (mirrors what the real service does at the top of #call).
      allow(Deploys::BuildAndConverge).to receive(:call) do |app:, deploy:|
        deploy.update!(builder: "wokkud")
        "archive rebuilt\n"
      end
      allow(Lifecycle::Ops).to receive(:issue!)

      described_class.perform_now(**base_args)

      expect(deploy.reload.image_ref).to eq(deploy.wokkud_image_ref)
    end

    it "does not fail the deploy when the registry-prune op issue errors" do
      allow(Lifecycle::Ops).to receive(:issue!).and_raise(StandardError, "op dispatch failed")
      described_class.perform_now(**base_args)
      deploy.reload
      expect(deploy.status).to eq("succeeded")
      expect(app.reload.status).to eq("running")
    end
  end

  describe "terminal-status re-entry guard" do
    let(:deploy) do
      create(:deploy, app_record: app, status: :succeeded, image_ref: "127.0.0.1:5000/wokku/#{app.name}:some-id")
    end

    it "no-ops on a retry against an already-terminal deploy — no rebuild, no re-converge" do
      expect(Deploys::BuildAndConverge).not_to receive(:call)
      expect(Lifecycle::Ops).not_to receive(:converge!)

      described_class.perform_now(**base_args)

      expect(deploy.reload.status).to eq("succeeded")
    end
  end

  describe "neither artifact present" do
    let(:deploy) { create(:deploy, app_record: app, status: :pending) }

    it "fails the deploy up front instead of wedging it in building — never converges or rebuilds" do
      expect(Deploys::BuildAndConverge).not_to receive(:call)
      expect(Lifecycle::Ops).not_to receive(:converge!)

      described_class.perform_now(**base_args)

      deploy.reload
      expect(deploy.status).to eq("failed")
      expect(deploy.log).to include("no rollback artifact")
      expect(deploy.finished_at).to be_present
    end

    it "leaves the app in its original status — never flipped to deploying/crashed" do
      original_status = app.status
      expect(original_status).not_to eq("deploying")

      described_class.perform_now(**base_args)

      expect(app.reload.status).to eq(original_status)
    end
  end

  describe "failure handling (image path)" do
    let(:deploy) { create(:deploy, app_record: app, image_ref: "127.0.0.1:5000/wokku/#{app.name}:some-id") }

    it "marks deploy as failed on Lifecycle::Ops::Failed" do
      op = build_stubbed(:lifecycle_op, status: :failed, kind: "stack.converge",
                                        error: "no route to host", error_code: "connect_failed")
      allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed.new(op))
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("failed")
      expect(app.reload.status).to eq("crashed")
      expect(deploy.reload.log).to include("stack.converge failed: no route to host (connect_failed)")
    end

    it "marks deploy as failed on Lifecycle::Ops::Timeout" do
      allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Timeout, "converge poll timed out")
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("failed")
      expect(app.reload.status).to eq("crashed")
    end

    it "marks deploy as timed_out on Timeout::Error" do
      allow(Lifecycle::Ops).to receive(:converge!).and_raise(Timeout::Error, "deploy timed out")
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("timed_out")
      expect(app.reload.status).to eq("crashed")
    end

    it "marks deploy as failed on Lifecycle::Ops::Busy (a restart/scale/wake racing this rollback), with the retry-shortly message in the log" do
      allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Busy.new(app))
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("failed")
      expect(app.reload.status).to eq("crashed")
      expect(deploy.reload.log).to include("another operation is in flight for #{app.name} — retry shortly")
    end
  end

  describe "failure handling (archive path)" do
    let(:archive_key) { "deploy-archives/#{app.id}/#{SecureRandom.uuid}.tar.gz" }
    let(:deploy) { create(:deploy, app_record: app, archive_key: archive_key) }

    it "marks deploy as failed on Deploys::BuildAndConverge::Error" do
      allow(Deploys::BuildAndConverge).to receive(:call)
        .and_raise(Deploys::BuildAndConverge::Error, "wokkud build failed: boom")
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("failed")
      expect(app.reload.status).to eq("crashed")
      expect(deploy.reload.log).to include("wokkud build failed: boom")
    end

    it "marks deploy as timed_out on Timeout::Error raised from BuildAndConverge's own budget" do
      allow(Deploys::BuildAndConverge).to receive(:call).and_raise(Timeout::Error, "deploy timed out")
      described_class.perform_now(**base_args)
      expect(deploy.reload.status).to eq("timed_out")
      expect(app.reload.status).to eq("crashed")
    end
  end
end

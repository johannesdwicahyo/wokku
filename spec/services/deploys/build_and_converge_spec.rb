# spec/services/deploys/build_and_converge_spec.rb
require "rails_helper"

RSpec.describe Deploys::BuildAndConverge do
  # Real records: wait_for_claim reloads deploy and server, and builder_busy?
  # is a real query — stubbed models can't exercise either.
  let(:server) { create(:server, wokkud_builds_enabled: true, heartbeat_at: Time.current, vitals: { "registry" => "ok" }) }
  let(:app_record) { create(:app_record, server: server) }
  let(:deploy) { create(:deploy, app_record: app_record, builder: "wokkud") }
  let(:service) { described_class.new(app: app_record, deploy: deploy) }

  # Speed: shrink every clock. CLAIM_WAIT=0.2s idle, cap=1s, poll=0.05s.
  before do
    stub_const("Deploys::BuildAndConverge::CLAIM_WAIT", 0.2)
    stub_const("Deploys::BuildAndConverge::QUEUE_WAIT_MAX", 1)
    stub_const("Deploys::BuildAndConverge::POLL", 0.05)
    allow(DeployChannel).to receive(:broadcast_to)
  end

  def busy_row!(picked_up_at: Time.current)
    other_app = create(:app_record, server: server)
    create(:deploy, app_record: other_app, builder: "wokkud",
           build_picked_up_at: picked_up_at, build_finished_at: nil)
  end

  describe "#wait_for_claim" do
    it "returns true as soon as the build is picked up" do
      deploy.update!(build_picked_up_at: Time.current)
      expect(service.send(:wait_for_claim, deploy, server)).to be(true)
    end

    it "gives up after CLAIM_WAIT of idle silence (sick-builder regression pin)" do
      expect(service.send(:wait_for_claim, deploy, server)).to be(false)
    end

    it "keeps waiting past CLAIM_WAIT while another build is in flight, and claims late" do
      busy_row!
      # Pick up our build after 3x the idle threshold — only busy-awareness
      # can carry the wait that far.
      picked_up = Thread.new do
        sleep 0.6
        deploy.update!(build_picked_up_at: Time.current)
      end
      expect(service.send(:wait_for_claim, deploy, server)).to be(true)
    ensure
      picked_up.join
    end

    it "does not count a wedged claim (older than BUSY_CLAIM_MAX_AGE) as busy" do
      busy_row!(picked_up_at: 13.minutes.ago)
      expect(service.send(:wait_for_claim, deploy, server)).to be(false)
    end

    it "gives up at QUEUE_WAIT_MAX even while continuously busy" do
      busy_row!
      started = Time.current
      expect(service.send(:wait_for_claim, deploy, server)).to be(false)
      expect(Time.current - started).to be < 3 # bounded by the 1s stubbed cap, not idle resets
    end

    it "bails out when the heartbeat goes stale mid-queue" do
      busy_row!
      server.update!(heartbeat_at: 1.hour.ago)
      expect(service.send(:wait_for_claim, deploy, server)).to be(false)
    end

    it "announces the queue exactly once in the log and over the channel" do
      busy_row!
      Thread.new { sleep 0.3; deploy.update!(build_picked_up_at: Time.current) }.tap do |t|
        service.send(:wait_for_claim, deploy, server)
        t.join
      end
      expect(deploy.reload.log).to include("queued behind another build")
      expect(deploy.log.scan("queued behind another build").size).to eq(1)
      expect(DeployChannel).to have_received(:broadcast_to)
        .with(deploy, hash_including(data: a_string_matching(/queued behind another build/))).once
    end
  end

  describe "#builder_busy?" do
    it "is true for a live claimed build on the same server" do
      busy_row!
      expect(service.send(:builder_busy?, deploy, server)).to be(true)
    end

    it "ignores finished builds, other servers, the current deploy, and non-wokkud builders" do
      busy_row!(picked_up_at: Time.current).update!(build_finished_at: Time.current)
      other_server_app = create(:app_record, server: create(:server))
      create(:deploy, app_record: other_server_app, builder: "wokkud", build_picked_up_at: Time.current)
      deploy.update!(build_picked_up_at: Time.current) # current deploy never counts
      create(:deploy, app_record: create(:app_record, server: server), builder: nil, build_picked_up_at: Time.current)
      expect(service.send(:builder_busy?, deploy, server)).to be(false)
    end
  end

  describe "give-up behavior (fail-loud for every app — no dokku fallback)" do
    before do
      allow(service).to receive(:wokkud_build?).and_return(true)
      allow(service).to receive(:wait_for_claim).and_return(false)
    end

    it "raises Error(BuilderUnavailable) when the claim wait gives up, for adopted apps too" do
      allow(app_record).to receive(:wokkud_native?).and_return(false)
      expect { service.call }.to raise_error(Deploys::BuildAndConverge::Error, /did not pick up the build/)
      expect(deploy.reload.builder).to eq("wokkud") # marker no longer cleared — there is nothing to fall back to
    end

    it "raises Error(BuilderUnavailable) at entry when the builder is sick" do
      allow(service).to receive(:wokkud_build?).and_return(false)
      expect { service.call }.to raise_error(Deploys::BuildAndConverge::Error, /builder unavailable/)
    end
  end

  describe "release" do
    it "always releases via Lifecycle::Ops.converge! and never touches dokku" do
      allow(service).to receive(:wokkud_build?).and_return(true)
      allow(service).to receive(:wait_for_claim).and_return(true)
      deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current, log: "built")
      expect(::Lifecycle::Ops).to receive(:converge!)
        .with(app_record, image_ref: deploy.wokkud_image_ref, deploy: deploy)
      expect(Hosts::Ssh).not_to receive(:new)

      expect(service.call).to eq("built")
    end

    it "raises Error when the build reported a failure" do
      allow(service).to receive(:wokkud_build?).and_return(true)
      allow(service).to receive(:wait_for_claim).and_return(true)
      deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current, build_error: "boom")
      expect { service.call }.to raise_error(Deploys::BuildAndConverge::Error, /wokkud build failed: boom/)
    end

    it "wraps Lifecycle::Ops::Busy (a restart/scale/wake racing this build's release) into Error like Failed/Timeout" do
      allow(service).to receive(:wokkud_build?).and_return(true)
      allow(service).to receive(:wait_for_claim).and_return(true)
      deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current, log: "built")
      allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Busy.new(app_record))
      expect { service.call }.to raise_error(Deploys::BuildAndConverge::Error, /retry shortly/)
    end
  end

  describe "timeout budget" do
    it "does not start DEPLOY_TIMEOUT until the build is picked up" do
      allow(service).to receive(:wokkud_build?).and_return(true)
      allow(service).to receive(:wait_for_claim).and_return(true)
      deploy.update!(build_picked_up_at: Time.current, build_finished_at: Time.current, log: "built")
      allow(::Lifecycle::Ops).to receive(:converge!)
      expect(Timeout).to receive(:timeout).with(Deploys::BuildAndConverge::DEPLOY_TIMEOUT.to_i).and_call_original
      service.call
    end
  end
end

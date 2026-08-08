# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deploys::RecordRollbackArtifact do
  let(:app) { create(:app_record) }
  let(:deploy) { create(:deploy, :wokkud, app_record: app, status: :succeeded, log: "build output") }

  describe ".call" do
    it "sets image_ref to the wokkud build tag already in the registry, with no Dokku/SSH call" do
      allow(Lifecycle::Ops).to receive(:issue!)

      result = described_class.call(deploy: deploy)

      expect(result).to eq(deploy.wokkud_image_ref)
      expect(deploy.reload.image_ref).to eq(deploy.wokkud_image_ref)
    end

    it "issues a registry.prune op for wokku/<app>, keep = newest MAX_ROLLBACK_TAGS deploys' image_ref suffixes" do
      older = (1..4).map do |days_ago|
        d = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: days_ago.days.ago)
        d.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{d.id}")
        d
      end
      # A 6th deploy, older than MAX_ROLLBACK_TAGS's window, must NOT be kept.
      too_old = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: 30.days.ago)
      too_old.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{too_old.id}")

      expect(Lifecycle::Ops).to receive(:issue!)
        .with(app, "registry.prune",
              { "repo" => "wokku/#{app.name}", "keep_tags" => ([ deploy ] + older).map { |d| d.id.to_s } },
              wait: false, timeout: anything)

      described_class.call(deploy: deploy)
      expect(too_old).to be_persisted # sanity: it exists but is excluded from the `.with` expectation above
    end

    it "rollback deploy's image_ref suffix (original deploy id) contributes to keep_tags, deduped" do
      # Create an original deploy that the rollback will point at
      original = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: 3.days.ago)
      original.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{original.id}")

      # Create a rollback deploy that references the original's tag (its id as suffix)
      rollback = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: 2.days.ago)
      rollback.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{original.id}")

      # Create 2 more normal deploys
      other1 = create(:deploy, :wokkud, app_record: app, status: :succeeded, created_at: 1.day.ago)
      other1.update_column(:image_ref, "127.0.0.1:5000/wokku/#{app.name}:#{other1.id}")

      # Newest 5 by created_at DESC are: deploy (now), other1 (1d), rollback (2d), original (3d)
      # But deploy + other1 + rollback + original = 4 items, all fit in the window
      # The rollback's suffix is original.id, so the kept tags include:
      # deploy.id, other1.id, original.id (from both original and rollback)
      # When deduped, we get: deploy.id, other1.id, original.id (3 unique tags)
      expected_tags = Set.new([ deploy.id, other1.id, original.id ].map(&:to_s))

      expect(Lifecycle::Ops).to receive(:issue!)
        .with(app, "registry.prune",
              { "repo" => "wokku/#{app.name}", "keep_tags" => match_array(expected_tags.to_a) },
              wait: false, timeout: anything)

      described_class.call(deploy: deploy)
    end

    it "leaves image_ref untouched on a non-wokkud (historical) deploy, but still issues the prune op" do
      legacy_deploy = create(:deploy, app_record: app, status: :succeeded, builder: "dokku", image_ref: nil)
      expect(Lifecycle::Ops).to receive(:issue!)
        .with(app, "registry.prune", { "repo" => "wokku/#{app.name}", "keep_tags" => [] }, wait: false, timeout: anything)

      result = described_class.call(deploy: legacy_deploy)

      expect(legacy_deploy.reload.image_ref).to be_nil
      expect(result).to be_nil
    end

    it "issues the prune op unconditionally even when the app has no wokkud deploys yet (agent 404s the repo, safely)" do
      legacy_deploy = create(:deploy, app_record: app, status: :succeeded, builder: "dokku")
      expect(Lifecycle::Ops).to receive(:issue!).with(app, "registry.prune", anything, wait: false, timeout: anything)

      expect { described_class.call(deploy: legacy_deploy) }.not_to raise_error
    end

    it "isolation contract: a prune op-issue failure never flips the deploy and returns nil" do
      allow(Lifecycle::Ops).to receive(:issue!).and_raise(StandardError, "op dispatch failed")

      result = nil
      expect { result = described_class.call(deploy: deploy) }.not_to raise_error

      expect(result).to be_nil
      # image_ref was already committed before the prune call raised — the
      # isolation contract only guarantees the DEPLOY's status/success is
      # never flipped, not that every write in #call is transactional.
      expect(deploy.reload.status).to eq("succeeded")
    end

    it "isolation contract: an error raised by deploy.update! itself (e.g. a DB deadlock) swallows and returns nil" do
      allow(deploy).to receive(:update!).and_raise(ActiveRecord::Deadlocked, "deadlock retry")

      result = nil
      expect { result = described_class.call(deploy: deploy) }.not_to raise_error
      expect(result).to be_nil
    end
  end
end

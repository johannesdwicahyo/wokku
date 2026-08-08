# frozen_string_literal: true

require "rails_helper"

RSpec.describe RollbackArtifactResolver do
  let(:app_record) { create(:app_record) }

  describe ".call" do
    it "resolves the image path via the registry when image_ref is registry-prefixed and the tag is live there" do
      deploy_id = "44444444-4444-4444-4444-444444444444"
      ref = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:#{deploy_id}"
      release = app_record.releases.create!(description: "registry-backed")
      deploy = app_record.deploys.create!(release: release, status: :succeeded, image_ref: ref)
      allow_any_instance_of(Hosts::Registry).to receive(:tags).with("wokku-rollback/#{app_record.name}").and_return([ deploy_id ])

      result = described_class.call(app_record: app_record, release: release, target_deploy: deploy)

      expect(result.artifact_available?).to be true
      expect(result.image_ref).to eq(ref)
      expect(result.archive_key).to be_nil
      expect(result.hint).to be_nil
    end

    it "falls back to the archive path when a registry-prefixed image_ref's tag is missing from the registry" do
      deploy_id = "55555555-5555-5555-5555-555555555555"
      ref = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:#{deploy_id}"
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      release = app_record.releases.create!(description: "registry-backed-missing")
      deploy = app_record.deploys.create!(release: release, status: :succeeded, image_ref: ref, archive_key: archive_key)
      allow_any_instance_of(Hosts::Registry).to receive(:tags).with("wokku-rollback/#{app_record.name}").and_return([])
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(true)

      result = described_class.call(app_record: app_record, release: release, target_deploy: deploy)

      expect(result.artifact_available?).to be true
      expect(result.archive_key).to eq(archive_key)
      expect(result.image_ref).to be_nil
    end

    it "treats a legacy non-registry image_ref as not-live (swept 2026-07-28) and falls back to the archive, without any host call" do
      tag = "wokku-rollback/#{app_record.name}:22222222-2222-2222-2222-222222222222"
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      release = app_record.releases.create!(description: "historical")
      deploy = app_record.deploys.create!(release: release, status: :succeeded, image_ref: tag, archive_key: archive_key)
      expect(Hosts::Ssh).not_to receive(:new)
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(true)

      result = described_class.call(app_record: app_record, release: release, target_deploy: deploy)

      expect(result.artifact_available?).to be true
      expect(result.archive_key).to eq(archive_key)
      expect(result.image_ref).to be_nil
    end

    it "reports unavailable with a hint when both the image tag and archive are gone" do
      deploy_id = "33333333-3333-3333-3333-333333333333"
      ref = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:#{deploy_id}"
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      release = app_record.releases.create!(description: "historical")
      deploy = app_record.deploys.create!(release: release, status: :succeeded, image_ref: ref, archive_key: archive_key)
      allow_any_instance_of(Hosts::Registry).to receive(:tags).with("wokku-rollback/#{app_record.name}").and_return([])
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(false)

      result = described_class.call(app_record: app_record, release: release, target_deploy: deploy)

      expect(result.artifact_available?).to be false
      expect(result.hint).to include("rollback image tag was pruned")
      expect(result.hint).to include("archive is no longer in storage")
    end

    it "reports unavailable with a legacy-deploy hint when the deploy recorded neither artifact" do
      release = app_record.releases.create!(description: "legacy-sha-only")
      deploy = app_record.deploys.create!(release: release, status: :succeeded, commit_sha: "deadbeef1234567")

      result = described_class.call(app_record: app_record, release: release, target_deploy: deploy)

      expect(result.artifact_available?).to be false
      expect(result.hint).to include("legacy deploy")
    end

    it "reports unavailable with a no-deploy hint when the release has no deploy at all" do
      release = app_record.releases.create!(description: "no-deploy-release")

      result = described_class.call(app_record: app_record, release: release, target_deploy: nil)

      expect(result.artifact_available?).to be false
      expect(result.hint).to include("no recorded deploy")
    end

    it "resolves the archive path directly when only archive_key was ever recorded" do
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      release = app_record.releases.create!(description: "tarball-only")
      deploy = app_record.deploys.create!(release: release, status: :succeeded, archive_key: archive_key)
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(true)

      result = described_class.call(app_record: app_record, release: release, target_deploy: deploy)

      expect(result.artifact_available?).to be true
      expect(result.archive_key).to eq(archive_key)
    end
  end
end

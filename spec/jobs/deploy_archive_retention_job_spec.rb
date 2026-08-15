# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeployArchiveRetentionJob, type: :job do
  let(:store) { instance_double(Wokku::Providers::LocalBackupStore) }

  before do
    allow(Wokku.config).to receive(:backup_store).and_return(store)
  end

  it "can be enqueued" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end

  context "when the store is not configured" do
    before { allow(store).to receive(:configured?).and_return(false) }

    it "does nothing" do
      expect(store).not_to receive(:delete)
      expect { described_class.perform_now }.not_to raise_error
    end
  end

  context "when the store is configured" do
    before do
      allow(store).to receive(:configured?).and_return(true)
      allow(store).to receive(:list_keys).with("deploy-archives/").and_return([])
    end

    it "prunes archive keys whose app_id no longer has an AppRecord" do
      live_app = create(:app_record)
      deleted_app_id = SecureRandom.uuid_v7

      allow(store).to receive(:list_keys).with("deploy-archives/").and_return([
        "deploy-archives/#{deleted_app_id}/a.tar.gz",
        "deploy-archives/#{deleted_app_id}/b.tar.gz",
        "deploy-archives/#{live_app.id}/c.tar.gz"
      ])
      allow(store).to receive(:delete)

      described_class.perform_now

      expect(store).to have_received(:delete).with("deploy-archives/#{deleted_app_id}/a.tar.gz")
      expect(store).to have_received(:delete).with("deploy-archives/#{deleted_app_id}/b.tar.gz")
      expect(store).not_to have_received(:delete).with("deploy-archives/#{live_app.id}/c.tar.gz")
    end

    it "leaves a live app's keys untouched when there are no orphans" do
      live_app = create(:app_record)

      allow(store).to receive(:list_keys).with("deploy-archives/").and_return([
        "deploy-archives/#{live_app.id}/c.tar.gz"
      ])
      allow(store).to receive(:delete)

      described_class.perform_now

      expect(store).not_to have_received(:delete)
    end

    it "isolates a failing orphan delete — other orphans still get pruned" do
      deleted_app_id_1 = SecureRandom.uuid_v7
      deleted_app_id_2 = SecureRandom.uuid_v7

      allow(store).to receive(:list_keys).with("deploy-archives/").and_return([
        "deploy-archives/#{deleted_app_id_1}/a.tar.gz",
        "deploy-archives/#{deleted_app_id_2}/b.tar.gz"
      ])
      allow(store).to receive(:delete) do |key|
        raise "boom" if key.include?(deleted_app_id_1)
      end

      expect { described_class.perform_now }.not_to raise_error

      expect(store).to have_received(:delete).with("deploy-archives/#{deleted_app_id_1}/a.tar.gz")
      expect(store).to have_received(:delete).with("deploy-archives/#{deleted_app_id_2}/b.tar.gz")
    end

    it "keeps the newest 5 archives per app and prunes the rest" do
      app = create(:app_record)
      deploys = Array.new(7) do |i|
        d = create(:deploy, :succeeded, app_record: app, archive_key: "deploy-archives/#{app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
        d
      end
      # deploys[0] is oldest (10 days ago) ... deploys[6] is newest (4 days ago)
      keep = deploys.last(5)
      prune = deploys.first(2)

      allow(store).to receive(:delete)

      described_class.perform_now

      prune.each do |d|
        expect(store).to have_received(:delete).with(d.archive_key)
        expect(d.reload.archive_key).to be_nil
      end

      keep.each do |d|
        expect(d.reload.archive_key).to eq("deploy-archives/#{app.id}/#{deploys.index(d)}.tar.gz")
      end
    end

    it "does not delete an object still referenced by a kept row — rollback rows share their target's archive_key" do
      app = create(:app_record)
      shared_key = "deploy-archives/#{app.id}/shared.tar.gz"

      # Old terminal deploy holding the shared key — old enough to fall
      # outside the newest-5 window on its own.
      old_original = create(:deploy, :succeeded, app_record: app, archive_key: shared_key)
      old_original.update_columns(created_at: 30.days.ago)

      # 5 newer terminal deploys; the newest is a rollback row that COPIED
      # the shared key from old_original (see RollbackArtifactResolver).
      4.times do |i|
        d = create(:deploy, :succeeded, app_record: app, archive_key: "deploy-archives/#{app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
      end
      rollback_row = create(:deploy, :succeeded, app_record: app, archive_key: shared_key)
      rollback_row.update_columns(created_at: 1.day.ago)

      allow(store).to receive(:delete)

      described_class.perform_now

      # 6 terminal rows, newest 5 kept — old_original falls outside the
      # window, but its key is still referenced by the kept rollback_row.
      expect(store).not_to have_received(:delete)
      expect(rollback_row.reload.archive_key).to eq(shared_key)
      expect(old_original.reload.archive_key).to eq(shared_key)
    end

    it "does not delete an object referenced by a NON-terminal row, even when every terminal reference is prunable" do
      app = create(:app_record)
      shared_key = "deploy-archives/#{app.id}/shared.tar.gz"

      old_terminal = create(:deploy, :succeeded, app_record: app, archive_key: shared_key)
      old_terminal.update_columns(created_at: 30.days.ago)
      # An in-flight rollback that copied the same key — its build still
      # needs the object in the bucket.
      in_flight = create(:deploy, app_record: app, status: :building, archive_key: shared_key)

      5.times do |i|
        d = create(:deploy, :succeeded, app_record: app, archive_key: "deploy-archives/#{app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
      end

      allow(store).to receive(:delete)

      described_class.perform_now

      expect(store).not_to have_received(:delete)
      expect(in_flight.reload.archive_key).to eq(shared_key)
      expect(old_terminal.reload.archive_key).to eq(shared_key)
    end

    it "nulls archive_key on EVERY row referencing a pruned key, deleting the object only once" do
      app = create(:app_record)
      shared_key = "deploy-archives/#{app.id}/shared.tar.gz"

      # Two old terminal rows sharing one key (an original + a finished
      # rollback to it), both outside the newest-5 window.
      old_original = create(:deploy, :succeeded, app_record: app, archive_key: shared_key)
      old_original.update_columns(created_at: 31.days.ago)
      old_rollback = create(:deploy, :succeeded, app_record: app, archive_key: shared_key)
      old_rollback.update_columns(created_at: 30.days.ago)

      5.times do |i|
        d = create(:deploy, :succeeded, app_record: app, archive_key: "deploy-archives/#{app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
      end

      allow(store).to receive(:delete)

      described_class.perform_now

      expect(store).to have_received(:delete).with(shared_key).once
      expect(old_original.reload.archive_key).to be_nil
      expect(old_rollback.reload.archive_key).to be_nil
    end

    it "does not touch pending/building deploys even if older than the newest 5" do
      app = create(:app_record)
      in_flight = create(:deploy, app_record: app, status: :pending,
        archive_key: "deploy-archives/#{app.id}/in-flight.tar.gz")
      in_flight.update_columns(created_at: 30.days.ago)
      5.times do |i|
        create(:deploy, :succeeded, app_record: app, archive_key: "deploy-archives/#{app.id}/#{i}.tar.gz")
      end

      expect(store).not_to receive(:delete)

      described_class.perform_now

      expect(in_flight.reload.archive_key).to eq("deploy-archives/#{app.id}/in-flight.tar.gz")
    end

    it "is idempotent — a second run finds nothing left to prune" do
      app = create(:app_record)
      7.times do |i|
        d = create(:deploy, :succeeded, app_record: app, archive_key: "deploy-archives/#{app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
      end
      allow(store).to receive(:delete)

      described_class.perform_now
      expect(store).to have_received(:delete).twice

      described_class.perform_now
      expect(store).to have_received(:delete).twice # no additional calls
    end

    it "isolates per-app failures — one app's error doesn't stop the sweep" do
      broken_app = create(:app_record)
      broken_deploys = Array.new(6) do |i|
        d = create(:deploy, :succeeded, app_record: broken_app, archive_key: "deploy-archives/#{broken_app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
        d
      end

      healthy_app = create(:app_record)
      healthy_deploys = Array.new(6) do |i|
        d = create(:deploy, :succeeded, app_record: healthy_app, archive_key: "deploy-archives/#{healthy_app.id}/#{i}.tar.gz")
        d.update_columns(created_at: (10 - i).days.ago)
        d
      end

      allow(store).to receive(:delete) do |key|
        raise "boom" if key.include?(broken_app.id.to_s)
      end

      expect { described_class.perform_now }.not_to raise_error

      # broken app's oldest archive was attempted but not nulled (delete raised)
      expect(broken_deploys.first.reload.archive_key).to eq("deploy-archives/#{broken_app.id}/0.tar.gz")
      # healthy app still got pruned normally
      expect(healthy_deploys.first.reload.archive_key).to be_nil
    end
  end
end

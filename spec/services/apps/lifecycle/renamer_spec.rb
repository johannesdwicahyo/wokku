require "rails_helper"

RSpec.describe Apps::Lifecycle::Renamer do
  let(:app) { app_records(:one) }
  let(:dns) { Wokku.config.dns_provider }

  before do
    allow(dns).to receive(:create_app_record)
    allow(dns).to receive(:delete_app_record)
  end

  describe "#call!" do
    it "returns the app unchanged when new_name equals current name" do
      result = described_class.new(app).call!(app.name)
      expect(result).to eq(app)
      expect(dns).not_to have_received(:create_app_record)
    end

    it "raises Apps::Lifecycle::Error on invalid name" do
      expect { described_class.new(app).call!("UPPERCASE_BAD") }
        .to raise_error(Apps::Lifecycle::Error, /name/i)
    end

    it "raises Apps::Lifecycle::Error if name is taken on the same server" do
      AppRecord.create!(name: "taken-already", server: app.server, team: app.team, created_by_id: app.team.users.first.id)
      expect { described_class.new(app).call!("taken-already") }
        .to raise_error(Apps::Lifecycle::Error, /taken/i)
    end

    it "renames the AppRecord, the canonical Domain row, and reshuffles DNS — no Dokku involved" do
      old_name = app.name
      zone = Wokku.config.canonical_domain
      domain = app.domains.create!(hostname: "#{old_name}.#{zone}")
      expect(Hosts::Ssh).not_to receive(:new)

      result = described_class.new(app).call!("renamed-app")

      expect(result.name).to eq("renamed-app")
      expect(app.reload.name).to eq("renamed-app")
      expect(domain.reload.hostname).to eq("renamed-app.#{zone}")
      expect(dns).to have_received(:create_app_record).with("renamed-app", app.server.host)
      expect(dns).to have_received(:delete_app_record).with(old_name)
    end

    it "keeps EnvVar rows riding the app across the rename" do
      app.env_vars.create!(key: "FOO", value: "bar")
      described_class.new(app).call!("renamed-app")
      expect(app.reload.env_vars.pluck(:key, :value)).to include([ "FOO", "bar" ])
    end

    it "moves the bare git repo to the new name (history rides; old path freed)" do
      old_name = app.name
      old_repo = instance_double(Git::BareRepo, exists?: true, path: "/git/#{old_name}.git")
      new_repo = instance_double(Git::BareRepo, exists?: false, path: "/git/renamed-app.git")
      allow(Git::BareRepo).to receive(:new).with(old_name).and_return(old_repo)
      allow(Git::BareRepo).to receive(:new).with("renamed-app").and_return(new_repo)
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:mv)

      described_class.new(app).call!("renamed-app")

      expect(FileUtils).to have_received(:mv).with("/git/#{old_name}.git", "/git/renamed-app.git")
    end

    it "removes the old repo instead when a repo already exists at the new name" do
      old_repo = instance_double(Git::BareRepo, exists?: true, path: "/git/old.git", remove!: nil)
      new_repo = instance_double(Git::BareRepo, exists?: true, path: "/git/renamed-app.git")
      allow(Git::BareRepo).to receive(:new).with(app.name).and_return(old_repo)
      allow(Git::BareRepo).to receive(:new).with("renamed-app").and_return(new_repo)

      described_class.new(app).call!("renamed-app")

      expect(old_repo).to have_received(:remove!)
    end

    it "does not let a failed bare repo move block the rename" do
      broken_repo = instance_double(Git::BareRepo)
      allow(broken_repo).to receive(:exists?).and_raise(Errno::ENOENT, "gone")
      allow(Git::BareRepo).to receive(:new).and_return(broken_repo)
      allow(Rails.logger).to receive(:warn)

      result = described_class.new(app).call!("renamed-app")

      expect(result.name).to eq("renamed-app")
      expect(Rails.logger).to have_received(:warn).with(/failed to move bare git repo/i)
    end
  end

  describe "wokkud-lifecycle swarm dance" do
    let(:image) { "127.0.0.1:5000/wokku/#{app.name}:abc" }

    before do
      app.update!(wokkud_lifecycle: true, swarm_port: 20_001)
      create(:lifecycle_op, app_record: app, status: :succeeded,
             params: { "image_ref" => image })
      allow(::Lifecycle::Ops).to receive(:converge!)
      allow(::Lifecycle::Ops).to receive(:remove!)
    end

    it "converges the new name on a fresh port with the OLD name's image ref, then removes the old stack under the old name" do
      old_name = app.name
      removed_as = nil
      allow(::Lifecycle::Ops).to receive(:remove!) { |a, **| removed_as = a.name }

      described_class.new(app).call!("renamed-app")

      expect(::Lifecycle::Ops).to have_received(:converge!) do |a, image_ref:|
        expect(a.name).to eq("renamed-app")
        expect(a.swarm_port).to be_nil # fresh port — old web still publishes 20001
        expect(image_ref).to eq(image) # wokku/<old-name> repo, resolved pre-rename
      end
      # stack.remove resolves the app name at claim time, so the removal ran
      # while the row briefly bore the old name — and ends on the new one.
      expect(removed_as).to eq(old_name)
      expect(app.reload.name).to eq("renamed-app")
    end

    it "keeps a stopped app stopped under its new name" do
      app.update!(status: :stopped)
      described_class.new(app).call!("renamed-app")
      expect(::Lifecycle::Ops).to have_received(:converge!)
        .with(app, image_ref: image, formation: { "web" => 0 }, allow_empty: true)
      expect(app.reload).to be_stopped
    end

    it "rolls back rows and swarm_port and raises loud when the new stack fails to start — old stack never touched" do
      old_name = app.name
      zone = Wokku.config.canonical_domain
      domain = app.domains.create!(hostname: "#{old_name}.#{zone}")
      allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Timeout, "not finished")

      expect { described_class.new(app).call!("renamed-app") }
        .to raise_error(Apps::Lifecycle::Error, /app unchanged.*not finished/m)

      expect(app.reload.name).to eq(old_name)
      expect(app.swarm_port).to eq(20_001)
      expect(domain.reload.hostname).to eq("#{old_name}.#{zone}")
      expect(::Lifecycle::Ops).not_to have_received(:remove!)
      expect(dns).not_to have_received(:create_app_record)
    end

    it "finishes the rename with a warning when old-stack removal fails (orphans are prunable)" do
      allow(::Lifecycle::Ops).to receive(:remove!).and_raise(::Lifecycle::Ops::Busy, app)
      allow(Rails.logger).to receive(:warn)

      described_class.new(app).call!("renamed-app")

      expect(app.reload.name).to eq("renamed-app")
      expect(Rails.logger).to have_received(:warn).with(/not removed/i)
    end

    it "seals a still-pending stack.remove op when removal times out — so a late claim can't tear down the NEW stack" do
      pending_op = create(:lifecycle_op, app_record: app, kind: "stack.remove", status: :pending, params: {})
      allow(::Lifecycle::Ops).to receive(:remove!).and_raise(::Lifecycle::Ops::Timeout, "not finished")
      allow(Rails.logger).to receive(:warn)

      described_class.new(app).call!("renamed-app")

      expect(pending_op.reload).to be_failed
      expect(app.reload.name).to eq("renamed-app")
    end

    it "skips the swarm dance entirely for a flagged app that was never deployed (no image)" do
      app.lifecycle_ops.destroy_all

      described_class.new(app).call!("renamed-app")

      expect(::Lifecycle::Ops).not_to have_received(:converge!)
      expect(::Lifecycle::Ops).not_to have_received(:remove!)
      expect(app.reload.name).to eq("renamed-app")
    end
  end

  # WOKKU_APP_ENABLED cutover: zone selection (which zone(s) a create/delete
  # actually hits) is Wokku.config.dns_provider's job now — see
  # spec/services/cloudflare/dns_provider_spec.rb. Renamer's own remaining
  # cutover-specific responsibility is the legacy-zone Domain row cleanup below.
  describe "legacy domain cleanup (WOKKU_APP_ENABLED cutover)" do
    it "flag ON: destroys the stale legacy-zone Domain row (its DNS record is deleted and never recreated)" do
      # Post-cutover identity is injected at boot (env flip = restart), so
      # simulate it on the config, not ENV.
      allow(Wokku.config).to receive_messages(
        canonical_domain: "wokku.app",
        owned_domains: [ "wokku.cloud", "wokku.app" ]
      )
      old_name = app.name
      legacy_row = app.domains.create!(hostname: "#{old_name}.wokku.cloud")
      canonical_row = app.domains.create!(hostname: "#{old_name}.wokku.app")

      described_class.new(app).call!("renamed-on")

      expect(Domain.exists?(legacy_row.id)).to be false
      expect(canonical_row.reload.hostname).to eq("renamed-on.wokku.app")
    end
  end
end

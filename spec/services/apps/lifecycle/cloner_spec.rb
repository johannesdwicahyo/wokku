require "rails_helper"

RSpec.describe Apps::Lifecycle::Cloner do
  let(:user)   { users(:one) }
  let(:source) { app_records(:one) }
  let(:dns)    { Wokku.config.dns_provider }

  before do
    allow(dns).to receive(:create_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, exists?: false, remove!: nil))
  end

  describe "#call!" do
    it "raises Apps::Lifecycle::Error on invalid new name" do
      expect { described_class.new(source, user: user).call!("BAD_NAME", skip_deploy: true) }
        .to raise_error(Apps::Lifecycle::Error, /name/i)
    end

    it "raises Apps::Lifecycle::Error if name is taken on the same server" do
      AppRecord.create!(name: "already-here", server: source.server, team: source.team, created_by_id: user.id)
      expect { described_class.new(source, user: user).call!("already-here", skip_deploy: true) }
        .to raise_error(Apps::Lifecycle::Error, /taken/i)
    end

    it "creates a fully-flagged native AppRecord, copies EnvVars, and mints DNS — no Dokku, no converge with skip_deploy" do
      source.env_vars.create!(key: "SECRET_TOKEN", value: "s3cret")
      expect(Hosts::Ssh).not_to receive(:new)
      expect(::Lifecycle::Ops).not_to receive(:converge!)

      expect { described_class.new(source, user: user).call!("clone-of-me", skip_deploy: true) }
        .to change(AppRecord, :count).by(1)

      new_app = AppRecord.find_by(name: "clone-of-me")
      expect(new_app.server_id).to eq(source.server_id)
      expect(new_app.team_id).to eq(source.team_id)
      expect(new_app.created_by_id).to eq(user.id)
      expect(new_app.container_port).to eq(source.container_port)
      expect(new_app).to be_wokkud_native
      expect(new_app).to be_wokkud_routed
      expect(new_app).to be_wokkud_git
      expect(new_app).to be_wokkud_lifecycle
      expect(new_app.env_vars.pluck(:key, :value).sort).to eq(source.env_vars.pluck(:key, :value).sort)
      expect(dns).to have_received(:create_app_record).with("clone-of-me", source.server.host)
    end

    it "clones the source bare repo so the clone is pushable" do
      src_repo = instance_double(Git::BareRepo, exists?: true, path: "/git/#{source.name}.git")
      dst_repo = instance_double(Git::BareRepo, path: "/git/clone-of-me.git")
      allow(dst_repo).to receive(:ensure!).and_return(dst_repo)
      allow(Git::BareRepo).to receive(:new).with(source.name).and_return(src_repo)
      allow(Git::BareRepo).to receive(:new).with("clone-of-me").and_return(dst_repo)
      cloner = described_class.new(source, user: user)
      allow(cloner).to receive(:system).and_return(true)

      cloner.call!("clone-of-me", skip_deploy: true)

      expect(cloner).to have_received(:system).with(
        "git", "-C", "/git/clone-of-me.git", "fetch", "--quiet",
        "/git/#{source.name}.git", "+refs/*:refs/*", exception: true
      )
    end

    it "does not let a failed bare repo copy block the clone" do
      src_repo = instance_double(Git::BareRepo, exists?: true, path: "/git/src.git")
      allow(Git::BareRepo).to receive(:new).and_return(src_repo)
      allow(src_repo).to receive(:ensure!).and_raise(Errno::EACCES, "denied")
      allow(Rails.logger).to receive(:warn)

      expect { described_class.new(source, user: user).call!("clone-of-me", skip_deploy: true) }
        .to change(AppRecord, :count).by(1)
      expect(Rails.logger).to have_received(:warn).with(/bare repo copy/i)
    end

    context "with skip_deploy: false" do
      it "converges via the source's wokkud-built deploy (image + commands ride the deploy)" do
        src_deploy = create(:deploy, :succeeded, :wokkud, app_record: source)
        expect(::Lifecycle::Ops).to receive(:converge!) do |a, deploy:|
          expect(a.name).to eq("clone-run")
          expect(deploy).to eq(src_deploy)
        end

        described_class.new(source, user: user).call!("clone-run", skip_deploy: false)
      end

      it "falls back to the source's last succeeded converge op for adopted apps" do
        create(:lifecycle_op, app_record: source, status: :succeeded,
               params: { "image_ref" => "127.0.0.1:5000/wokku/my-app-one:adopt-1",
                         "formation_commands" => { "web" => "bundle exec puma" } })
        expect(::Lifecycle::Ops).to receive(:converge!) do |a, image_ref:, formation_commands:|
          expect(a.name).to eq("clone-adopt")
          expect(image_ref).to eq("127.0.0.1:5000/wokku/my-app-one:adopt-1")
          expect(formation_commands).to eq({ "web" => "bundle exec puma" })
        end

        described_class.new(source, user: user).call!("clone-adopt", skip_deploy: false)
      end

      it "fails with the lifecycle error contract and leaves no AppRecord when the source has no usable image" do
        expect {
          expect { described_class.new(source, user: user).call!("clone-noimg", skip_deploy: false) }
            .to raise_error(Apps::Lifecycle::Error, /no deployable image/i)
        }.not_to change(AppRecord, :count)
      end

      it "wraps a converge failure as Apps::Lifecycle::Error and leaves no AppRecord" do
        create(:deploy, :succeeded, :wokkud, app_record: source)
        allow(::Lifecycle::Ops).to receive(:converge!)
          .and_raise(::Lifecycle::Ops::Timeout, "not finished")

        expect {
          expect { described_class.new(source, user: user).call!("clone-fail", skip_deploy: false) }
            .to raise_error(Apps::Lifecycle::Error, /failed to start.*not finished/m)
        }.not_to change(AppRecord, :count)
      end
    end
  end

  # WOKKU_APP_ENABLED cutover: which zone(s) a create actually hits is
  # Wokku.config.dns_provider's job now (see
  # spec/services/cloudflare/dns_provider_spec.rb). Cloner's own contract —
  # it always calls create_app_record with the new name — is covered by the
  # "mints DNS" example above.
end

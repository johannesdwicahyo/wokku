# frozen_string_literal: true

require "rails_helper"

# Coverage variant — exercises the destroy_apps / destroy_databases cascade
# and their rescue branches. The base hard_delete_account_job_spec.rb covers
# the no-op guards + PII nulling on a user with no apps/dbs.
RSpec.describe HardDeleteAccountJob, type: :job do
  let(:user)   { create(:user) }
  let(:team)   { create(:team, owner: user) }
  let(:server) { create(:server, team: team) }

  before do
    TeamMembership.find_or_create_by!(user: user, team: team) { |m| m.role = "admin" }
    # Default: the DNS provider + the git repo are inert no-ops.
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))
  end

  describe "destroy_apps" do
    let!(:app) { create(:app_record, team: team, server: server, creator: user) }

    it "routes the app through Apps::Destroyer, deletes DNS, and removes the AppRecord" do
      expect(Wokku.config.dns_provider).to receive(:delete_app_record).with(app.name)

      expect {
        described_class.perform_now(user.id)
      }.to change { AppRecord.exists?(app.id) }.from(true).to(false)
    end

    it "swallows a Destroyer best-effort failure (e.g. DNS) and still removes the row" do
      allow(Wokku.config.dns_provider).to receive(:delete_app_record).and_raise(StandardError, "cf 500")

      expect {
        described_class.perform_now(user.id)
      }.to change { AppRecord.exists?(app.id) }.from(true).to(false)
    end

    it "logs and continues when Apps::Destroyer.call itself raises (outer per-app rescue)" do
      allow(::Apps::Destroyer).to receive(:call).and_raise(StandardError, "fk constraint")
      expect(Rails.logger).to receive(:error).with(/error processing app/)

      # PII still gets nulled even though the app row survives.
      described_class.perform_now(user.id)
      expect(user.reload.deleted?).to be(true)
    end
  end

  describe "destroy_databases" do
    let!(:app) { create(:app_record, team: team, server: server, creator: user) }
    let!(:db) do
      create(:database_service, server: server, service_type: "postgres", name: "userdb")
        .tap { |d| d.update_column(:creator_id, user.id) }
    end

    before do
      AppDatabase.create!(app_record: app, database_service: db, alias_name: "DATABASE")
      allow(Rails.logger).to receive(:error) # outer rescues may fire
    end

    it "is destroyed via DatabaseProvisioner.destroy! exactly once (Apps::Destroyer catches it; the sweep doesn't double-process)" do
      expect(DatabaseProvisioner).to receive(:destroy!).with(database_service: db).once do |database_service:|
        database_service.destroy
      end

      expect {
        described_class.perform_now(user.id)
      }.to change { DatabaseService.exists?(db.id) }.from(true).to(false)
    end

    it "sweeps a creator-owned DB with no remaining linked apps via DatabaseProvisioner.destroy!" do
      orphan = create(:database_service, server: server, service_type: "postgres", name: "orphandb")
                 .tap { |d| d.update_column(:creator_id, user.id) }
      allow(DatabaseProvisioner).to receive(:destroy!) { |database_service:| database_service.destroy }

      described_class.perform_now(user.id)

      expect(DatabaseProvisioner).to have_received(:destroy!).with(database_service: orphan)
      expect(DatabaseService.exists?(orphan.id)).to be(false)
    end

    it "skips a creator-owned DB still linked to a surviving app (belonging to another team)" do
      other_team = create(:team)
      other_app = create(:app_record, team: other_team)
      shared_db = create(:database_service, server: server, service_type: "postgres", name: "shareddb")
                    .tap { |d| d.update_column(:creator_id, user.id) }
      AppDatabase.create!(app_record: other_app, database_service: shared_db, alias_name: "DATABASE")
      allow(DatabaseProvisioner).to receive(:destroy!) { |database_service:| database_service.destroy }

      described_class.perform_now(user.id)

      expect(DatabaseProvisioner).not_to have_received(:destroy!).with(database_service: shared_db)
      expect(DatabaseService.exists?(shared_db.id)).to be(true)
    end

    it "logs and continues when the sweep's DatabaseProvisioner.destroy! raises (outer rescue)" do
      orphan = create(:database_service, server: server, service_type: "postgres", name: "orphandb")
                 .tap { |d| d.update_column(:creator_id, user.id) }
      allow(DatabaseProvisioner).to receive(:destroy!) do |database_service:|
        raise StandardError, "boom" if database_service == orphan
        database_service.destroy
      end
      expect(Rails.logger).to receive(:error).with(/error processing db/).at_least(:once)

      described_class.perform_now(user.id)
      expect(user.reload.deleted?).to be(true)
    end
  end

  it "never references Dokku:: anywhere in the job" do
    source = File.read(Wokku::Engine.root.join("app/jobs/hard_delete_account_job.rb"))
    expect(source).not_to match(/Dokku::/)
  end

  describe "activity logging" do
    it "logs a user.hard_deleted activity with the admin_email" do
      expect(Activity).to receive(:log).with(
        hash_including(action: "user.hard_deleted",
                       metadata: hash_including(admin_email: "boss@wokku.cloud"))
      )
      described_class.perform_now(user.id, admin_email: "boss@wokku.cloud")
    end
  end
end

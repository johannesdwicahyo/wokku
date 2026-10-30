# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardDeleteAccountJob, type: :job do
  let(:user) do
    u = User.create!(email: "todelete-#{SecureRandom.hex(4)}@example.com",
                     password: "password123456",
                     deletion_scheduled_at: 1.day.ago)
    team = Team.create!(name: "Delete Test Team", owner: u)
    TeamMembership.create!(user: u, team: team, role: "admin")
    u
  end

  it "no-ops if user has already been hard-deleted" do
    original_deleted_at = 1.hour.ago
    user.update_columns(deleted_at: original_deleted_at)
    expect { described_class.perform_now(user.id) }.not_to raise_error
    expect(user.reload.deleted_at.to_i).to be_within(2).of(original_deleted_at.to_i)
  end

  it "no-ops if user not found" do
    expect { described_class.perform_now("00000000-0000-0000-0000-000000000000") }.not_to raise_error
  end

  it "nulls PII columns on user" do
    described_class.perform_now(user.id)
    user.reload
    expect(user.deleted?).to be_truthy
    expect(user.email).to match(/^deleted-/)
    expect(user.encrypted_password).to eq("")
    expect(user.name).to be_nil
    expect(user.avatar_url).to be_nil
    expect(user.provider).to be_nil
    expect(user.uid).to be_nil
  end

  # "preserves DepositTransaction rows" removed in 1.8 — the table is gone.

  it "hard delete is idempotent (second call is safe)" do
    described_class.perform_now(user.id)
    expect { described_class.perform_now(user.id) }.not_to raise_error
  end

  it "removes the app's bare git repo during destroy_apps (via Apps::Destroyer)" do
    app = create(:app_record, creator: user, team: user.teams.first)
    repo = instance_double(Git::BareRepo, remove!: true)

    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).with(app.name).and_return(repo)

    described_class.perform_now(user.id)

    expect(repo).to have_received(:remove!)
  end

  # C2: flagged apps must issue stack.remove before the record cascade —
  # Apps::Destroyer's remove! call carries this through unchanged.
  it "issues Lifecycle::Ops.remove! for a flagged app before destroying it" do
    app = create(:app_record, creator: user, team: user.teams.first, wokkud_lifecycle: true)
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))

    expect(Lifecycle::Ops).to receive(:remove!).with(app, wait: true)
    described_class.perform_now(user.id)
    expect(AppRecord.where(id: app.id)).not_to exist
  end

  it "routes each app through Apps::Destroyer" do
    app = create(:app_record, creator: user, team: user.teams.first)
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))

    expect(::Apps::Destroyer).to receive(:call).with(app).and_call_original
    described_class.perform_now(user.id)
  end

  # Host apps (the managed cloud's billing teardown) hook after_update_commit
  # on deleted_at — update_columns would silently skip them.
  it "marks deleted_at through a callback-firing save" do
    user # create before the expectation (create! also calls save!)
    expect_any_instance_of(User).to receive(:save!).with(validate: false).and_call_original
    described_class.perform_now(user.id)
    expect(user.reload.deleted_at).to be_present
  end

  it "never references Dokku:: anywhere in the job" do
    source = File.read(Wokku::Engine.root.join("app/jobs/hard_delete_account_job.rb"))
    expect(source).not_to match(/Dokku::/)
  end

  describe "teams the user only belongs to" do
    let(:org) { create(:team) }
    let!(:membership) { TeamMembership.create!(user: user, team: org, role: "member") }
    let!(:org_app) { create(:app_record, team: org, creator: user) }
    let!(:own_app) { create(:app_record, team: user.owned_teams.first, creator: user) }

    before do
      allow(Wokku.config.dns_provider).to receive(:delete_app_record)
      allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))
    end

    it "destroys owned-team apps only and drops the membership" do
      described_class.perform_now(user.id)
      expect(AppRecord.where(id: own_app.id)).not_to exist
      expect(AppRecord.where(id: org_app.id)).to exist
      expect(Team.where(id: org.id)).to exist
      expect(TeamMembership.where(id: membership.id)).not_to exist
    end

    it "keeps a user-created database linked to the other team's app" do
      db = create(:database_service, creator_id: user.id)
      create(:app_database, app_record: org_app, database_service: db)
      expect(DatabaseProvisioner).not_to receive(:destroy!).with(database_service: db)
      described_class.perform_now(user.id)
      expect(DatabaseService.where(id: db.id)).to exist
    end
  end

  describe "Apple" do
    let(:apple_user) do
      create(:user, apple_uid: "001.del", provider: "apple", uid: "001.del").tap do |u|
        u.remember_apple_refresh_token!("r1", client_id: "cloud.wokku.signin")
      end
    end

    it "revokes the Apple token and clears every Apple column" do
      expect(Apple::Client).to receive(:revoke).with("r1", client_id: "cloud.wokku.signin").and_return(true)
      described_class.perform_now(apple_user.id)
      apple_user.reload
      expect([ apple_user.apple_uid, apple_user.apple_refresh_token, apple_user.apple_token_client_id ]).to eq([ nil, nil, nil ])
    end

    it "finishes the deletion and reports when revoke fails" do
      allow(Apple::Client).to receive(:revoke).and_return(false)
      expect(Sentry).to receive(:capture_message).with(/Apple revoke failed/, hash_including(extra: { user_id: apple_user.id }))
      described_class.perform_now(apple_user.id)
      expect(apple_user.reload).to be_deleted
    end

    it "lets the same Apple ID sign up again as a new account" do
      allow(Apple::Client).to receive(:revoke).and_return(true)
      described_class.perform_now(apple_user.id)
      fresh = User.from_apple({ "sub" => "001.del", "email" => "again@example.com", "email_verified" => true })
      expect(fresh).to be_persisted
      expect(fresh.id).not_to eq(apple_user.id)
    end

    it "does not call Apple for users without a token" do
      plain = create(:user)
      expect(Apple::Client).not_to receive(:revoke)
      described_class.perform_now(plain.id)
    end
  end
end

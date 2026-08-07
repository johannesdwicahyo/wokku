require "rails_helper"

RSpec.describe AppRecord do
  let(:owner)  { User.create!(email: "app-owner@example.com", password: "password123456") }
  let(:team)   { Team.create!(name: "app-team", owner: owner) }
  let(:server) { Server.create!(name: "app-server", host: "10.0.0.1", team: team) }

  describe "validations" do
    it "is valid" do
      app = AppRecord.new(name: "my-app", server: server, team: team, creator: owner)
      expect(app).to be_valid
    end

    it "requires name" do
      app = AppRecord.new(server: server, team: team, creator: owner)
      expect(app).not_to be_valid
      expect(app.errors[:name]).to include("can't be blank")
    end

    it "name must be lowercase alphanumeric with hyphens" do
      app = AppRecord.new(name: "My_App", server: server, team: team, creator: owner)
      expect(app).not_to be_valid
      expect(app.errors[:name]).to include("must be lowercase alphanumeric with hyphens")
    end

    it "name cannot start with a number" do
      app = AppRecord.new(name: "1app", server: server, team: team, creator: owner)
      expect(app).not_to be_valid
    end

    it "name cannot start with a hyphen" do
      app = AppRecord.new(name: "-app", server: server, team: team, creator: owner)
      expect(app).not_to be_valid
    end

    it "accepts name with hyphens" do
      app = AppRecord.new(name: "my-cool-app", server: server, team: team, creator: owner)
      expect(app).to be_valid
    end

    it "name unique within server" do
      AppRecord.create!(name: "unique-app", server: server, team: team, creator: owner)
      duplicate = AppRecord.new(name: "unique-app", server: server, team: team, creator: owner)
      expect(duplicate).not_to be_valid
    end

    it "same name allowed on different servers" do
      other_server = Server.create!(name: "other-server", host: "10.0.0.2", team: team)
      AppRecord.create!(name: "shared-name", server: server, team: team, creator: owner)
      app2 = AppRecord.new(name: "shared-name", server: other_server, team: team, creator: owner)
      expect(app2).to be_valid
    end
  end

  describe "status enum" do
    it "defaults to running" do
      app = AppRecord.new(name: "status-app", server: server, team: team, creator: owner)
      expect(app.status).to eq("running")
    end

    it "includes all expected values" do
      expect(AppRecord.statuses).to eq({ "running" => 0, "stopped" => 1, "crashed" => 2, "deploying" => 3, "sleeping" => 4, "created" => 5 })
    end

    it "can set status to stopped" do
      app = AppRecord.create!(name: "stop-app", server: server, team: team, creator: owner)
      app.stopped!
      expect(app.stopped?).to be true
    end
  end

  describe "defaults" do
    it "deploy_branch defaults to main" do
      app = AppRecord.new(name: "branch-app", server: server, team: team, creator: owner)
      expect(app.deploy_branch).to eq("main")
    end
  end

  describe "scopes" do
    it "stale returns records with old or nil synced_at" do
      fresh = AppRecord.create!(name: "fresh-app", server: server, team: team, creator: owner, synced_at: 1.minute.ago)
      stale = AppRecord.create!(name: "stale-app", server: server, team: team, creator: owner, synced_at: 10.minutes.ago)
      nil_sync = AppRecord.create!(name: "nil-app", server: server, team: team, creator: owner, synced_at: nil)

      stale_apps = AppRecord.stale
      expect(stale_apps).not_to include(fresh)
      expect(stale_apps).to include(stale)
      expect(stale_apps).to include(nil_sync)
    end
  end

  describe "associations" do
    it "belongs to server" do
      app = AppRecord.create!(name: "assoc-app", server: server, team: team, creator: owner)
      expect(app.server).to eq(server)
    end

    it "belongs to team" do
      app = AppRecord.create!(name: "team-app", server: server, team: team, creator: owner)
      expect(app.team).to eq(team)
    end

    it "belongs to creator" do
      app = AppRecord.create!(name: "creator-app", server: server, team: team, creator: owner)
      expect(app.creator).to eq(owner)
    end

    it "responds to has_many associations" do
      app = app_records(:one)
      %i[releases deploys domains env_vars notifications].each do |assoc|
        expect(app).to respond_to(assoc)
      end
    end
  end

  describe "encryption" do
    it "encrypts webhook secrets at rest" do
      app = AppRecord.create!(
        name: "crypto-check", server: server, team: team, creator: owner,
        git_webhook_secret: "secret-abc-123",
        github_webhook_secret: "secret-def-456"
      )

      raw_git    = ActiveRecord::Base.connection.execute("SELECT git_webhook_secret FROM app_records WHERE id = '#{app.id}'").first
      raw_github = ActiveRecord::Base.connection.execute("SELECT github_webhook_secret FROM app_records WHERE id = '#{app.id}'").first

      expect(raw_git["git_webhook_secret"]).not_to eq("secret-abc-123")
      expect(raw_github["github_webhook_secret"]).not_to eq("secret-def-456")
      expect(app.reload.git_webhook_secret).to eq("secret-abc-123")
      expect(app.reload.github_webhook_secret).to eq("secret-def-456")
    end
  end

  describe ".lookup!" do
    it "finds by uuid" do
      app = AppRecord.create!(name: "lookup-uuid", server: server, team: team, creator: owner)
      expect(AppRecord.lookup!(app.id)).to eq(app)
    end

    it "finds by name" do
      app = AppRecord.create!(name: "lookup-name", server: server, team: team, creator: owner)
      expect(AppRecord.lookup!("lookup-name")).to eq(app)
    end

    it "raises RecordNotFound for unknown name" do
      expect { AppRecord.lookup!("does-not-exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound for unknown uuid" do
      expect { AppRecord.lookup!("00000000-0000-0000-0000-000000000000") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#mounts_for_converge" do
    it "is empty when no mounts are declared" do
      expect(create(:app_record).mounts_for_converge).to eq([])
    end

    it "names one volume per container path" do
      app = create(:app_record, name: "nextcloud-abcd", storage_mounts: [ "/var/www/html", "/data" ])
      expect(app.mounts_for_converge).to eq([
        { "volume" => "wokku-nextcloud-abcd-var-www-html", "path" => "/var/www/html" },
        { "volume" => "wokku-nextcloud-abcd-data", "path" => "/data" }
      ])
    end

    it "disambiguates paths sharing a basename" do
      app = create(:app_record, name: "app", storage_mounts: [ "/a/data", "/b/data" ])
      volumes = app.mounts_for_converge.map { |m| m["volume"] }
      expect(volumes.uniq.length).to eq(2), "colliding volume names would silently share one volume"
    end
  end
end

require "rails_helper"

RSpec.describe AppRecord, "preview associations and uniqueness" do
  let(:owner)  { User.create!(email: "preview-owner@example.com", password: "password123456") }
  let(:team)   { Team.create!(name: "preview-team", owner: owner) }
  let(:server) { Server.create!(name: "preview-server", host: "10.0.0.3", team: team) }

  let!(:main_app) do
    AppRecord.create!(name: "my-app", server: server, team: team, creator: owner, is_preview: false)
  end

  let!(:preview_app) do
    AppRecord.create!(
      name: "my-app-pr-42",
      server: server, team: team, creator: owner,
      is_preview: true, pr_number: 42, parent_app_id: main_app.id
    )
  end

  describe "scopes" do
    it "main_apps excludes preview apps" do
      main_apps = AppRecord.main_apps
      expect(main_apps).to include(main_app)
      expect(main_apps).not_to include(preview_app)
    end

    it "previews returns only preview apps" do
      previews = AppRecord.previews
      expect(previews).to include(preview_app)
      expect(previews).not_to include(main_app)
    end

    it "is_preview defaults to false" do
      app = AppRecord.new(name: "new-app", server: server, team: team, creator: owner)
      expect(app.is_preview).to eq(false)
    end
  end

  describe "associations" do
    it "main app has many preview apps" do
      expect(main_app.preview_apps).to include(preview_app)
    end

    it "preview app belongs to parent app" do
      expect(preview_app.parent_app).to eq(main_app)
    end

    it "destroying main app cascades to preview apps" do
      preview_id = preview_app.id
      main_app.destroy
      expect(AppRecord.find_by(id: preview_id)).to be_nil
    end

    it "preview app stores pr_number" do
      expect(preview_app.pr_number).to eq(42)
    end

    it "parent_app is optional (regular apps have no parent)" do
      expect(main_app.parent_app).to be_nil
    end
  end

  describe "uniqueness index" do
    it "cannot create two preview apps for the same parent and PR number" do
      duplicate = AppRecord.new(
        name: "my-app-pr-42-copy",
        server: server, team: team, creator: owner,
        is_preview: true, pr_number: 42, parent_app_id: main_app.id
      )
      expect(duplicate).not_to be_valid
    end

    it "can have different PR numbers for same parent app" do
      other_preview = AppRecord.new(
        name: "my-app-pr-99",
        server: server, team: team, creator: owner,
        is_preview: true, pr_number: 99, parent_app_id: main_app.id
      )
      expect(other_preview).to be_valid
    end
  end
end

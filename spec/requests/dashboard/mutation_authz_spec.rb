# frozen_string_literal: true

require "rails_helper"

# Security hotfix pins: dashboard mutations on add-ons/databases must scope
# both the app and the database to the caller and authorize the right role —
# same rules as the API (api/v1/addons#destroy, api/v1/databases#link/unlink).
RSpec.describe "Dashboard mutation authorization", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:team_admin) { users(:one) } # admin of team one
  let(:app_one) { app_records(:one) }
  let(:team) { app_one.team }
  let(:foreign_app) { app_records(:two) }
  let(:foreign_db) { database_services(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: team, role: :viewer) } }
  let(:member) { create(:user).tap { |u| create(:team_membership, user: u, team: team, role: :member) } }
  let(:db) { servers(:one).database_services.create!(name: "authz-pg", service_type: "postgres", status: :running, wokkud_managed: true, dsn: "postgres://user:pass@host:5432/db") }

  before do
    allow(DatabaseProvisioner).to receive(:destroy!)
    allow(Apps::Restarter).to receive(:restart)
    allow(Services::Ops).to receive(:issue_and_wait!)
  end

  describe "DELETE /dashboard/apps/:app_id/resources (add-on destroy)" do
    before { app_one.app_databases.create!(database_service: db, alias_name: "DATABASE") }

    it "404s for a database that is not attached to the app (another team's)" do
      sign_in team_admin
      delete "/dashboard/apps/#{app_one.id}/resources", params: { addon_id: foreign_db.id }
      expect(response).to have_http_status(:not_found)
      expect(DatabaseProvisioner).not_to have_received(:destroy!)
    end

    it "404s for another team's app" do
      sign_in team_admin
      delete "/dashboard/apps/#{foreign_app.id}/resources", params: { addon_id: foreign_db.id }
      expect(response).to have_http_status(:not_found)
      expect(DatabaseProvisioner).not_to have_received(:destroy!)
    end

    it "is forbidden for a team member who is not a team admin" do
      sign_in member
      delete "/dashboard/apps/#{app_one.id}/resources", params: { addon_id: db.id }
      expect(flash[:alert]).to match(/not authorized/)
      expect(DatabaseProvisioner).not_to have_received(:destroy!)
      expect(DatabaseService.exists?(db.id)).to be(true)
    end

    it "destroys the add-on for a team admin" do
      sign_in team_admin
      delete "/dashboard/apps/#{app_one.id}/resources", params: { addon_id: db.id }
      expect(response).to redirect_to("/dashboard/apps/#{app_one.id}/resources")
      expect(DatabaseProvisioner).to have_received(:destroy!).with(database_service: db)
    end
  end

  describe "POST /dashboard/addons/:id/link" do
    it "is forbidden for a viewer and writes nothing" do
      sign_in viewer
      post "/dashboard/addons/#{db.id}/link", params: { app_id: app_one.id }
      expect(flash[:alert]).to match(/not authorized/)
      expect(AppDatabase.where(database_service: db)).to be_empty
      expect(app_one.env_vars.find_by(key: "POSTGRES_URL")).to be_nil
      expect(Apps::Restarter).not_to have_received(:restart)
    end

    it "links for a member" do
      sign_in member
      post "/dashboard/addons/#{db.id}/link", params: { app_id: app_one.id }
      expect(flash[:notice]).to match(/Linked/)
      expect(AppDatabase.where(database_service: db, app_record: app_one)).to exist
    end

    it "404s for another team's app" do
      sign_in team_admin
      post "/dashboard/addons/#{db.id}/link", params: { app_id: foreign_app.id }
      expect(response).to have_http_status(:not_found)
      expect(AppDatabase.where(database_service: db)).to be_empty
    end
  end

  describe "POST /dashboard/addons/:id/unlink" do
    before do
      AppDatabase.create!(app_record: app_one, database_service: db, alias_name: "DB")
      app_one.env_vars.create!(key: "DB_URL", value: "postgres://user:pass@host/db")
    end

    it "is forbidden for a viewer and keeps the link and env" do
      sign_in viewer
      post "/dashboard/addons/#{db.id}/unlink", params: { app_id: app_one.id }
      expect(flash[:alert]).to match(/not authorized/)
      expect(AppDatabase.where(database_service: db, app_record: app_one)).to exist
      expect(app_one.env_vars.find_by(key: "DB_URL")).to be_present
    end

    it "unlinks for a member" do
      sign_in member
      post "/dashboard/addons/#{db.id}/unlink", params: { app_id: app_one.id }
      expect(flash[:notice]).to match(/Unlinked/)
      expect(AppDatabase.where(database_service: db, app_record: app_one)).not_to exist
    end

    it "404s for another team's app even when it is linked to the database" do
      AppDatabase.create!(app_record: foreign_app, database_service: db, alias_name: "DB")
      sign_in team_admin
      post "/dashboard/addons/#{db.id}/unlink", params: { app_id: foreign_app.id }
      expect(response).to have_http_status(:not_found)
      expect(AppDatabase.where(database_service: db, app_record: foreign_app)).to exist
    end
  end

  # Cron entries run commands inside the app — writes need member+, same as
  # api/v1/scheduled_tasks (not just the show? the controller gates reads on).
  describe "scheduled tasks writes" do
    let(:task) { create(:scheduled_task, app_record: app_one) }

    before { [ viewer, member ].each { |u| u.update!(plan: create(:plan, :pro)) } }

    it "forbids a viewer from creating a task" do
      sign_in viewer
      expect {
        post "/dashboard/apps/#{app_one.id}/scheduled_tasks", params: { scheduled_task: { command: "ls", schedule: "* * * * *" } }
      }.not_to change(ScheduledTask, :count)
      expect(flash[:alert]).to match(/not authorized/)
    end

    it "forbids a viewer from removing a task" do
      task
      sign_in viewer
      delete "/dashboard/apps/#{app_one.id}/scheduled_tasks/#{task.id}"
      expect(flash[:alert]).to match(/not authorized/)
      expect(ScheduledTask.exists?(task.id)).to be(true)
    end

    it "lets a member create a task" do
      allow_any_instance_of(Apps::Cron::TaskCreator).to receive(:call!).and_return(task)
      sign_in member
      post "/dashboard/apps/#{app_one.id}/scheduled_tasks", params: { scheduled_task: { command: "ls", schedule: "* * * * *" } }
      expect(flash[:notice]).to match(/added/)
    end
  end
end

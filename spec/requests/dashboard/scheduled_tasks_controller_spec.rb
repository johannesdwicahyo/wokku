# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::ScheduledTasks", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }

  describe "GET index" do
    it "renders the scheduled-tasks page (with the new-task form) for a plan that has the feature" do
      user.update!(plan: create(:plan, :pro))
      sign_in user

      get dashboard_app_scheduled_tasks_path(app_record)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("new_scheduled_task")
      # The form must post to the real route helper, not the AppRecord-inferred one.
      expect(response.body).to include("action=\"#{dashboard_app_scheduled_tasks_path(app_record)}\"")
    end

    it "renders without the form for a plan that lacks the feature" do
      user.update!(plan: create(:plan, :free))
      sign_in user

      get dashboard_app_scheduled_tasks_path(app_record)

      expect(response).to have_http_status(:ok)
    end

    it "shows recent run results (status, timing, log excerpt)" do
      user.update!(plan: create(:plan, :pro))
      sign_in user
      task = create(:scheduled_task, app_record: app_record)
      create(:scheduled_task_run, scheduled_task: task, exit_code: 7,
             started_at: 2.minutes.ago, finished_at: 1.minute.ago,
             log_excerpt: "boom-marker")

      get dashboard_app_scheduled_tasks_path(app_record)

      expect(response.body).to include("exit 7")
      expect(response.body).to include("boom-marker")
    end

    it "renders a skipped run" do
      user.update!(plan: create(:plan, :pro))
      sign_in user
      task = create(:scheduled_task, app_record: app_record)
      create(:scheduled_task_run, scheduled_task: task, exit_code: nil,
             skipped_reason: "already-running", log_excerpt: nil)

      get dashboard_app_scheduled_tasks_path(app_record)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("skipped (already-running)")
    end

    # Carry-forward from Task 1: log_excerpt is byteslice-trimmed to 16KB on
    # write, which can split a multibyte char and leave an invalid-encoding
    # tail. The view calls `.scrub` so such a tail renders as replacement
    # chars instead of raising in ERB. (PG rejects invalid bytes on write, so
    # this can't round-trip through the DB — guard the render helper directly.)
    it "scrubs an invalid-encoding log_excerpt instead of raising" do
      bad = (+"tail\xE2").force_encoding("UTF-8")
      expect(bad.valid_encoding?).to be(false)
      expect { bad.to_s.scrub }.not_to raise_error
      expect(bad.to_s.scrub.valid_encoding?).to be(true)
    end
  end

  describe "pro-feature gate, create and destroy" do
    before { sign_in user }

    it "GET new renders the form" do
      get new_dashboard_app_scheduled_task_path(app_record)
      expect(response).to have_http_status(:ok)
    end

    it "redirects with an upgrade hint when the plan lacks the feature" do
      allow(Wokku.config.plan_enforcer).to receive(:allowed?)
        .with(anything, :feature, slug: :scheduled_tasks).and_return(false)
      post dashboard_app_scheduled_tasks_path(app_record),
           params: { scheduled_task: { command: "ls", schedule: "* * * * *" } }
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match(/Upgrade to Pro/)
    end

    it "POST create adds a task and redirects" do
      creator = instance_double(Apps::Cron::TaskCreator)
      allow(Apps::Cron::TaskCreator).to receive(:new).with(app_record).and_return(creator)
      expect(creator).to receive(:call!)
        .with(command: "ls -la", schedule: "*/5 * * * *", description: "list")
      post dashboard_app_scheduled_tasks_path(app_record),
           params: { scheduled_task: { command: "ls -la", schedule: "*/5 * * * *", description: "list" } }
      expect(response).to redirect_to(dashboard_app_scheduled_tasks_path(app_record))
      expect(flash[:notice]).to eq("Scheduled task added.")
    end

    it "POST create re-renders index with 422 on a cron error" do
      creator = instance_double(Apps::Cron::TaskCreator)
      allow(Apps::Cron::TaskCreator).to receive(:new).and_return(creator)
      allow(creator).to receive(:call!).and_raise(Apps::Cron::Error.new("bad schedule", code: :invalid))
      post dashboard_app_scheduled_tasks_path(app_record),
           params: { scheduled_task: { command: "ls", schedule: "nope" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("bad schedule")
    end

    it "DELETE destroy removes the task and redirects" do
      task = create(:scheduled_task, app_record: app_record)
      destroyer = instance_double(Apps::Cron::TaskDestroyer)
      allow(Apps::Cron::TaskDestroyer).to receive(:new).with(app_record).and_return(destroyer)
      expect(destroyer).to receive(:call!).with(task)
      delete dashboard_app_scheduled_task_path(app_record, task)
      expect(response).to redirect_to(dashboard_app_scheduled_tasks_path(app_record))
      expect(flash[:notice]).to eq("Scheduled task removed.")
    end

    it "DELETE destroy surfaces a cron error as an alert" do
      task = create(:scheduled_task, app_record: app_record)
      destroyer = instance_double(Apps::Cron::TaskDestroyer)
      allow(Apps::Cron::TaskDestroyer).to receive(:new).and_return(destroyer)
      allow(destroyer).to receive(:call!).and_raise(Apps::Cron::Error.new("host down", code: :host))
      delete dashboard_app_scheduled_task_path(app_record, task)
      expect(response).to redirect_to(dashboard_app_scheduled_tasks_path(app_record))
      expect(flash[:alert]).to eq("Couldn't remove: host down")
    end
  end
end

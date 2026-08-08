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
end

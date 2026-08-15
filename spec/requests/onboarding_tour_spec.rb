# frozen_string_literal: true

require "rails_helper"

RSpec.describe "First-app guided tour", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "User onboarding state model" do
    it "defaults new users to pending at step 0" do
      u = create(:user)
      expect(u.onboarding_status).to eq("pending")
      expect(u.onboarding_step).to eq(0)
    end

    it "exposes tour_active? only when active" do
      u = create(:user)
      expect(u.tour_active?).to be(false)
      u.update!(onboarding_status: :active)
      expect(u.tour_active?).to be(true)
    end

    it "tour_finished? when completed or skipped" do
      u = create(:user, onboarding_status: :completed)
      expect(u.tour_finished?).to be(true)
      u.update!(onboarding_status: :skipped)
      expect(u.tour_finished?).to be(true)
    end
  end

  describe "activation on dashboard" do
    let(:user) { create(:user) } # pending by default
    before { sign_in user }

    it "activates the tour on first dashboard visit with zero apps" do
      get "/dashboard/apps"
      expect(user.reload.onboarding_status).to eq("active")
      expect(user.onboarding_step).to eq(0)
    end

    it "stashes onboarding_tour_started in the analytics flash on activation" do
      # Engine adaptation: the OSS engine has no shared/_analytics partial
      # (optional_partial hook — the cloud host supplies it), so the event
      # lives in the flash and must never leak into visible markup.
      get "/dashboard/apps"
      expect(flash[:posthog_event]).to eq("onboarding_tour_started")
      expect(response.body).not_to include("onboarding_tour_started")
    end

    it "silently completes (no tour) if a pending user already has apps" do
      team = create(:team, owner: user)
      create(:team_membership, team: team, user: user, role: :admin)
      server = create(:server, team: team)
      create(:app_record, team: team, creator: user, server: server)

      with_analytics_enabled do
        get "/dashboard/apps"
        expect(user.reload.onboarding_status).to eq("completed")
        # Bridge must NOT emit the started event when no tour is activated
        expect(response.body).not_to include(%q{posthog.capture("onboarding_tour_started")})
      end
    end

    it "does not re-activate a finished tour" do
      user.update!(onboarding_status: :skipped)
      get "/dashboard/apps"
      expect(user.reload.onboarding_status).to eq("skipped")
    end
  end

  describe "lifecycle transitions" do
    describe "#activate_tour!" do
      it "transitions pending → active at step 0" do
        u = create(:user, onboarding_status: :pending, onboarding_step: 0)
        u.activate_tour!
        expect(u.reload.onboarding_status).to eq("active")
        expect(u.onboarding_step).to eq(0)
      end

      it "is a NO-OP when already completed (stays completed)" do
        u = create(:user, onboarding_status: :completed, onboarding_step: 2)
        u.activate_tour!
        u.reload
        expect(u.onboarding_status).to eq("completed")
        expect(u.onboarding_step).to eq(2)
      end

      it "is a NO-OP when already active (stays active)" do
        u = create(:user, onboarding_status: :active, onboarding_step: 1)
        u.activate_tour!
        u.reload
        expect(u.onboarding_status).to eq("active")
        expect(u.onboarding_step).to eq(1)
      end
    end

    describe "#advance_tour_to" do
      it "advances to a higher step when active" do
        u = create(:user, onboarding_status: :active, onboarding_step: 1)
        u.advance_tour_to(3)
        expect(u.reload.onboarding_step).to eq(3)
      end

      it "does NOT regress to a lower step (monotonic guard)" do
        u = create(:user, onboarding_status: :active, onboarding_step: 3)
        u.advance_tour_to(1)
        expect(u.reload.onboarding_step).to eq(3)
      end

      it "does NOT advance to the same step (monotonic guard)" do
        u = create(:user, onboarding_status: :active, onboarding_step: 2)
        u.advance_tour_to(2)
        expect(u.reload.onboarding_step).to eq(2)
      end

      it "is a NO-OP when not active (pending)" do
        u = create(:user, onboarding_status: :pending, onboarding_step: 0)
        u.advance_tour_to(2)
        expect(u.reload.onboarding_step).to eq(0)
      end

      it "is a NO-OP when not active (completed)" do
        u = create(:user, onboarding_status: :completed, onboarding_step: 2)
        u.advance_tour_to(5)
        expect(u.reload.onboarding_step).to eq(2)
      end
    end

    describe "#complete_tour!" do
      it "transitions active → completed" do
        u = create(:user, onboarding_status: :active)
        u.complete_tour!
        expect(u.reload.onboarding_status).to eq("completed")
      end

      it "is a NO-OP when already skipped (stays skipped)" do
        u = create(:user, onboarding_status: :skipped)
        u.complete_tour!
        expect(u.reload.onboarding_status).to eq("skipped")
      end

      it "is a NO-OP when already completed (stays completed)" do
        u = create(:user, onboarding_status: :completed)
        u.complete_tour!
        expect(u.reload.onboarding_status).to eq("completed")
      end
    end

    describe "#skip_tour!" do
      it "transitions active → skipped" do
        u = create(:user, onboarding_status: :active)
        u.skip_tour!
        expect(u.reload.onboarding_status).to eq("skipped")
      end

      it "is a NO-OP when already completed (stays completed)" do
        u = create(:user, onboarding_status: :completed)
        u.skip_tour!
        expect(u.reload.onboarding_status).to eq("completed")
      end

      it "is a NO-OP when already skipped (stays skipped)" do
        u = create(:user, onboarding_status: :skipped)
        u.skip_tour!
        expect(u.reload.onboarding_status).to eq("skipped")
      end
    end
  end

  describe "skip endpoint" do
    let(:user) { create(:user, onboarding_status: :active, onboarding_step: 1) }
    before { sign_in user }

    it "marks the tour skipped" do
      patch "/dashboard/onboarding/skip"
      expect(user.reload.onboarding_status).to eq("skipped")
    end

    it "stashes onboarding_tour_skipped with the step in the analytics flash" do
      # Engine adaptation: no analytics partial in the OSS engine — assert the
      # flash the controller sets for the (cloud-supplied) bridge to consume.
      patch "/dashboard/onboarding/skip"
      expect(flash[:posthog_event]).to eq("onboarding_tour_skipped")
      expect(flash[:posthog_props]).to eq({ step: 1 })
    end

    it "is idempotent for a finished tour" do
      user.update!(onboarding_status: :completed)
      patch "/dashboard/onboarding/skip"
      expect(user.reload.onboarding_status).to eq("completed")
    end
  end

  describe "waypoint advances" do
    let(:user) { create(:user, onboarding_status: :active, onboarding_step: 0) }
    before { sign_in user }

    it "advances to step 2 when opening the Astro template during the tour" do
      get "/dashboard/templates/astro"
      expect(user.reload.onboarding_step).to be >= 2
    end

    it "does not advance for a non-tour user" do
      user.update!(onboarding_status: :skipped, onboarding_step: 0)
      get "/dashboard/templates/astro"
      expect(user.reload.onboarding_step).to eq(0)
    end
  end

  describe "step-3 funnel event persists across template#create redirect" do
    # Design: the tour user already has one app so the new create becomes app #2.
    # current_user.app_records.count == 2 after create → first_deploy_started does NOT fire.
    # This cleanly isolates the onboarding_tour_step event without first_deploy_started clobbering it.
    # When both conditions would apply (first deploy + tour step), first_deploy_started is written
    # last and wins — the ordering in templates_controller preserves the money-path event.
    let(:user) { create(:user, onboarding_status: :active, onboarding_step: 2) }
    let!(:team) do
      t = create(:team, owner: user)
      create(:team_membership, team: t, user: user, role: :admin)
      t
    end
    let!(:server) { create(:server, team: team) }

    before do
      # Pre-existing app so this create is NOT the user's first (count becomes 2 after create).
      create(:app_record, team: team, creator: user, server: server)
      sign_in user
    end

    it "stashes onboarding_tour_step with step 3 after posting astro template create" do
      # Engine adaptation: no analytics partial in the OSS engine — the
      # persistent flash carries the event across the redirect instead.
      post "/dashboard/templates", params: {
        template_slug: "astro",
        server_id: server.id,
        app_name: "astro-tour-test"
      }
      expect(user.reload.onboarding_step).to eq(3)
      expect(flash[:posthog_event]).to eq("onboarding_tour_step")
      expect(flash[:posthog_props]).to eq({ step: 3 })
    end
  end

  describe "step-5 coachmark mount and s5_retry copy value" do
    # Request specs can only assert the server-rendered mount div; the retry link
    # itself is built client-side by the Stimulus controller (Playwright verifies the link).
    let(:user) { create(:user, onboarding_status: :active, onboarding_step: 5) }
    before { sign_in user }

    it "does NOT render the tour mount without the cloud billing host (self-host guard)" do
      # Engine adaptation: _onboarding_tour.html.erb only renders when
      # dashboard_billing_path exists (the tour narrates the cloud free tier);
      # the OSS engine has no billing routes, so the mount must be absent.
      get "/dashboard/apps"
      expect(response.body).not_to include('data-controller="onboarding-tour"')
    end
  end

  describe "posthog funnel bridge" do
    it "stashes started on activation and skipped on skip in the analytics flash" do
      # Engine adaptation: no analytics partial in the OSS engine — the flash
      # is the bridge contract the cloud host consumes.
      u = create(:user)
      sign_in u
      get "/dashboard/apps"
      expect(flash[:posthog_event]).to eq("onboarding_tour_started")

      u2 = create(:user, onboarding_status: :active, onboarding_step: 1)
      sign_in u2
      patch "/dashboard/onboarding/skip"
      expect(flash[:posthog_event]).to eq("onboarding_tour_skipped")
      expect(flash[:posthog_props]).to eq({ step: 1 })
    end
  end

  describe "deploy status -> live / failure" do
    let(:user) { create(:user, onboarding_status: :active, onboarding_step: 3) }
    before { sign_in user }

    def give_app(status:, deploy_status:)
      team = create(:team, owner: user)
      create(:team_membership, team: team, user: user, role: :admin)
      server = create(:server, team: team)
      app = create(:app_record, team: team, creator: user, server: server, status: status)
      dep = create(:deploy, app_record: app, status: deploy_status)
      [ app, dep ]
    end

    it "completes the tour when the deploy view shows a succeeded deploy" do
      # Engine adaptation: no analytics partial in the OSS engine — assert the
      # flash.now event the controller sets instead of rendered posthog JS.
      app, dep = give_app(status: :running, deploy_status: :succeeded)
      get "/dashboard/apps/#{app.id}/deploys/#{dep.id}"
      expect(user.reload.onboarding_status).to eq("completed")
      expect(flash[:posthog_event]).to eq("onboarding_tour_completed")
    end

    it "moves to the failure step (5) when the deploy failed, not completed" do
      app, dep = give_app(status: :crashed, deploy_status: :failed)
      get "/dashboard/apps/#{app.id}/deploys/#{dep.id}"
      expect(user.reload.onboarding_status).to eq("active")
      expect(user.onboarding_step).to eq(5)
      expect(flash[:posthog_event]).to eq("onboarding_tour_failed")
      expect(flash[:posthog_props]).to eq({ step: 5 })
    end
  end

  describe "defensive backfill: NULL onboarding_status" do
    it "the backfill SQL sets onboarding_status=2 for any NULL rows (regression guard for PG::NotNullViolation)" do
      # The column is NOT NULL in the schema, so we can't create a truly-NULL row
      # through ActiveRecord. Instead we:
      #   1. Verify the migration SQL is idempotent on rows that already have a value
      #      (running it again must not change completed→0 or similar).
      #   2. Verify the SQL targets *only* NULL rows (WHERE onboarding_status IS NULL)
      #      by executing against the real DB with no NULLs present → 0 rows updated.
      u = create(:user, onboarding_status: :pending)

      rows_updated = ActiveRecord::Base.connection.execute(
        "UPDATE users SET onboarding_status = 2 WHERE onboarding_status IS NULL"
      ).cmd_tuples

      expect(rows_updated).to eq(0)          # no NULLs → 0 rows touched
      expect(u.reload.onboarding_status).to eq("pending") # existing row unchanged
    end

    it "the migration SQL expression (onboarding_status = 2) maps to :completed" do
      # Confirms the magic integer 2 in the migration matches the enum value
      # so a backfilled user is treated as 'completed', not some other state.
      u = create(:user, onboarding_status: :pending)
      ActiveRecord::Base.connection.execute(
        "UPDATE users SET onboarding_status = 2 WHERE id = '#{u.id}'"
      )
      expect(u.reload.onboarding_status).to eq("completed")
    end
  end
end

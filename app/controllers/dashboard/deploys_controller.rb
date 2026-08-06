module Dashboard
  class DeploysController < BaseController
    include OnboardingTourable
    # Team-wide deploys feed — one row per deploy across every app the
    # current user can see. Vercel-style observability page; complements
    # the per-app deploy log on apps#show.
    def index
      @deploys = Deploy
        .joins(:app_record)
        .where(app_record: policy_scope(AppRecord).main_apps)
        .includes(app_record: :server)
        .order(created_at: :desc)
        .limit(50)
    end

    def show
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :show?
      @deploy = @app.deploys.find(params[:id])

      if current_user.tour_active?
        case @deploy.status
        when "succeeded"
          current_user.complete_tour!
          flash.now[:posthog_event] = "onboarding_tour_completed"
        when "failed", "timed_out"
          current_user.advance_tour_to(5)
          flash.now[:posthog_event] = "onboarding_tour_failed"
          flash.now[:posthog_props] = { step: 5 }
        else
          advance_onboarding_to(3)
        end
      end
    end
  end
end

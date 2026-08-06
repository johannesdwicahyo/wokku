module Dashboard
  class OnboardingController < BaseController
    # Skip the first-app tour (permanent — never auto-shows again).
    def skip
      step = current_user.onboarding_step
      current_user.skip_tour!
      flash[:posthog_event] = "onboarding_tour_skipped"
      flash[:posthog_props] = { step: step }
      # Redirect straight to the apps landing (not dashboard_root_path, which
      # 301s here) so the analytics flash renders on a single redirect hop.
      redirect_to dashboard_apps_path
    end
  end
end

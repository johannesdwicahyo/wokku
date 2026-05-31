module Dashboard
  class OnboardingController < BaseController
    # Skip the first-app tour (permanent — never auto-shows again).
    def skip
      step = current_user.onboarding_step
      current_user.skip_tour!
      flash[:posthog_event] = "onboarding_tour_skipped"
      flash[:posthog_props] = { step: step }
      redirect_to dashboard_root_path
    end
  end
end

# frozen_string_literal: true

# Shared first-app-tour waypoint logic. Included by dashboard/templates/
# deploys controllers. State is advanced server-side so a reload always
# re-derives the correct step. Steps: 0 welcome, 1 pick, 2 confirm,
# 3 deploying, 4 live, 5 failure. See the design doc.
module OnboardingTourable
  extend ActiveSupport::Concern

  private

  def maybe_activate_onboarding!
    return unless current_user.onboarding_pending?

    if current_user.app_records.exists?
      current_user.complete_tour! # self-served; no tour
    else
      current_user.activate_tour!
      # Persistent flash (not flash.now) so the PostHog event survives the
      # redirect triggered by the flash[:deploy_template] guard that may
      # fire immediately after this call in AppsController#index.
      # After the toast fix this key is filtered out of _flash.html.erb and
      # will only ever reach shared/_analytics.html.erb.
      flash[:posthog_event] = "onboarding_tour_started"
    end
  end

  def advance_onboarding_to(step)
    return unless current_user.tour_active?
    current_user.advance_tour_to(step)
    # flash.now is intentional here: advance_onboarding_to is called on
    # pages that render inline (no redirect), so the event is captured on
    # the same response that triggered the step advance.
    flash.now[:posthog_event] = "onboarding_tour_step"
    flash.now[:posthog_props] = { step: step }
  end
end

# frozen_string_literal: true

# Helpers for enabling the PostHog analytics bridge inside request specs.
#
# The `analytics_enabled?` helper method in ApplicationController is gated
# to Rails.env.production? + POSTHOG_API_KEY so it never fires in tests by
# default. Use `with_analytics_enabled` to stub it true for the duration of
# a single example, allowing assertions against the real posthog.capture(...)
# output from shared/_analytics.html.erb.
#
# Usage:
#
#   it "emits onboarding_tour_started" do
#     with_analytics_enabled do
#       get "/dashboard"
#       expect(response.body).to include(%q{posthog.capture("onboarding_tour_started")})
#     end
#   end
module AnalyticsHelpers
  # Stubs analytics_enabled? to return true on every controller instance
  # for the duration of the given block, then restores the real behaviour.
  def with_analytics_enabled
    allow_any_instance_of(ApplicationController).to receive(:analytics_enabled?).and_return(true)
    yield
  end
end

RSpec.configure do |config|
  config.include AnalyticsHelpers, type: :request
end

module Organisms
  # Sign-in / 2FA shell: the form column on the left (logo, language switch,
  # content, legal footer) and a decorative light wall on the right that wakes
  # as the #signin-form is typed in. Below 960px the aside is not displayed, so
  # the wall never draws. Region + clock follow TopBarComponent.
  class AuthShellComponent < ApplicationComponent
    ZONE = TopBarComponent::ZONE
    FORM_ID = "signin-form".freeze

    def initialize(region: ENV["WOKKU_REGION"].presence, now: Time.current)
      @region = region
      @now = now
    end
    attr_reader :region

    def clock_text = @now.in_time_zone(ZONE).strftime("%H:%M:%S")

    # Status / Privacy / Terms are cloud routes; a self-host has none of them.
    def footer_links
      { status_path: "signin.footer.status", privacy_path: "signin.footer.privacy", terms_path: "signin.footer.terms" }
        .filter_map { |route, key| [ t(key), helpers.public_send(route) ] if helpers.respond_to?(route) }
    end
  end
end

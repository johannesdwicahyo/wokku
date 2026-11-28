module Molecules
  # One sign-in provider button: Devise's omniauth POST (button_to, no Turbo)
  # with the signup_started track event. The wide one is the primary (GitHub);
  # the others are outline cells of a 2-column grid showing the bare name. The
  # accessible name is always "Continue with X".
  class OauthButtonComponent < ApplicationComponent
    # provider => [display name, track value, route helper]
    PROVIDERS = {
      github:        [ "GitHub",    "github",    :user_github_omniauth_authorize_path ],
      google_oauth2: [ "Google",    "google",    :user_google_oauth2_omniauth_authorize_path ],
      apple:         [ "Apple",     "apple",     :user_apple_omniauth_authorize_path ],
      gitlab:        [ "GitLab",    "gitlab",    :user_gitlab_omniauth_authorize_path ],
      bitbucket:     [ "Bitbucket", "bitbucket", :user_bitbucket_omniauth_authorize_path ]
    }.freeze
    ORDER = PROVIDERS.keys.freeze

    # Brand marks from docs/brand/mockups/wokku-sign-in.html, verbatim; the
    # monochrome GitHub/Apple marks use currentColor (ink, or dark on the primary).
    ICONS = {
      github: '<path fill="currentColor" d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.78 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.84 1.19 3.1 0 4.42-2.69 5.39-5.26 5.68.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5z"/>',
      google_oauth2: '<path fill="#4285F4" d="M23.5 12.27c0-.82-.07-1.6-.2-2.36H12v4.46h6.45a5.5 5.5 0 0 1-2.39 3.62v3h3.86c2.26-2.08 3.58-5.15 3.58-8.72z"/><path fill="#34A853" d="M12 24c3.24 0 5.96-1.07 7.95-2.91l-3.86-3c-1.08.72-2.45 1.15-4.09 1.15-3.14 0-5.8-2.12-6.75-4.98H1.26v3.1A12 12 0 0 0 12 24z"/><path fill="#FBBC05" d="M5.25 14.26A7.2 7.2 0 0 1 4.87 12c0-.79.14-1.55.38-2.26v-3.1H1.26A12 12 0 0 0 0 12c0 1.94.46 3.77 1.26 5.36l3.99-3.1z"/><path fill="#EA4335" d="M12 4.76c1.77 0 3.35.61 4.6 1.8l3.43-3.43A11.5 11.5 0 0 0 12 0 12 12 0 0 0 1.26 6.64l3.99 3.1C6.2 6.88 8.86 4.76 12 4.76z"/>',
      apple: '<path fill="currentColor" d="M16.37 12.73c-.03-2.66 2.17-3.94 2.27-4-1.24-1.81-3.16-2.06-3.85-2.09-1.64-.17-3.2.97-4.03.97-.83 0-2.11-.94-3.47-.92-1.79.03-3.43 1.04-4.35 2.63-1.86 3.22-.48 7.99 1.33 10.6.89 1.28 1.94 2.71 3.33 2.66 1.34-.05 1.84-.86 3.46-.86 1.61 0 2.07.86 3.48.84 1.44-.03 2.35-1.3 3.23-2.59 1.02-1.48 1.44-2.92 1.46-2.99-.03-.01-2.8-1.08-2.83-4.26zM13.71 4.92c.74-.9 1.24-2.14 1.1-3.38-1.06.04-2.35.71-3.11 1.6-.68.79-1.28 2.06-1.12 3.27 1.18.09 2.39-.6 3.13-1.49z"/>',
      gitlab: '<path fill="#FC6D26" d="m23.6 9.6-.03-.09-3.26-8.5a.85.85 0 0 0-1.62.06l-2.2 6.74H7.5L5.3 1.07a.85.85 0 0 0-1.62-.06L.43 9.5l-.03.09a6.05 6.05 0 0 0 2 6.99l.01.01 4.98 3.73 2.46 1.86 1.5 1.13a1 1 0 0 0 1.22 0l1.5-1.13 2.46-1.86 5.01-3.75a6.05 6.05 0 0 0 2-6.98z"/>',
      bitbucket: '<path fill="#2684FF" d="M.78 1.21a.77.77 0 0 0-.77.89l3.26 19.8c.08.5.51.86 1.01.87h15.64c.38 0 .7-.27.77-.64L23.95 2.1a.77.77 0 0 0-.77-.89zM14.52 15.5H9.53l-1.35-7.05h7.55z"/>'
    }.freeze

    def initialize(provider:, wide: false)
      @provider = provider.to_sym
      @name, @track, @route = PROVIDERS.fetch(@provider)
      @wide = wide
    end
    attr_reader :provider, :wide

    def path = helpers.public_send(@route)
    def icon = ICONS.fetch(provider).html_safe # rubocop:disable Rails/OutputSafety -- constant markup
    def accessible_name = t("signin.continue_with", provider: @name)
    def label = wide ? accessible_name : @name

    def data
      { turbo: false, controller: "track", action: "click->track#capture",
        track_event_value: "signup_started", track_props_value: { provider: @track }.to_json }
    end

    def button_classes
      Atoms::ButtonComponent.new(variant: wide ? :primary : :secondary, class: "w-full h-[46px] text-[12px]").classes
    end
  end
end

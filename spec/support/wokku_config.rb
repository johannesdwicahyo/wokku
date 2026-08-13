# frozen_string_literal: true

# The ported engine specs were written against the cloud's canonical/owned
# domains. The engine's domain identity is config-driven, so set the test
# harness to those values rather than rewriting every domain assertion.
RSpec.configure do |config|
  config.before(:suite) do
    Wokku.configure do |c|
      c.canonical_domain = "wokku.cloud"
      c.owned_domains    = [ "wokku.app", "wokku.cloud" ]
      # Ported specs assume the cloud's OPEN registration (OAuth signup
      # creates users). Self-host default is closed; the closed-reg test in
      # spec/lib/wokku/providers_spec.rb flips it false locally + restores.
      c.open_registration = true
    end
    # Mailers generate absolute URLs (unlock/heartbeat/etc.); give them a host.
    Rails.application.config.action_mailer.default_url_options = { host: "wokku.cloud" }
    ActionMailer::Base.default_url_options = { host: "wokku.cloud" }
  end
end

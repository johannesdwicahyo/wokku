# Top-level feature flags that govern visible UI behavior for the
# current launch phase. Kept in one place so that expanding beyond
# Indonesia later is a one-line flip (or an env override), not a hunt
# across the view tree.

module Wokku
  module LaunchMode
    # While we operate in Indonesia only, regulators require IDR for
    # local payments and we haven't enabled Stripe/USD for end users.
    # Hide the USD UI (deposit flow, currency toggle) and default new
    # users to IDR. Flip by setting WOKKU_IDR_ONLY=0 when expanding.
    #
    # Default off in test so the legacy USD-behavior specs keep passing
    # without per-test stubbing; production + dev default on. Tests
    # that need to exercise IDR-only behavior explicitly stub this.
    def self.idr_only?
      default = Rails.env.test? ? "0" : "1"
      ENV.fetch("WOKKU_IDR_ONLY", default) == "1"
    end
  end
end

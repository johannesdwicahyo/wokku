module UtmCapturable
  extend ActiveSupport::Concern

  UTM_KEYS = %w[source medium campaign content term].freeze
  UTM_VALUE_LIMIT = 64

  private

  # Persists Meta/Google ad UTM params into the session so any subsequent
  # POST (signup, vps_pain_lead, plan upgrade) can attribute. Only the
  # 5 canonical keys; values are length-capped to defend against
  # garbage referrers stuffing the session.
  #
  # Wire via:
  #   include UtmCapturable
  #   before_action :stash_utms
  def stash_utms
    fresh = UTM_KEYS.each_with_object({}) do |k, h|
      v = params["utm_#{k}"]
      h[k] = v.to_s[0, UTM_VALUE_LIMIT] if v.present?
    end
    session[:utm] = fresh if fresh.any?
  end
end

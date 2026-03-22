class PagesController < ApplicationController
  layout "application"

  skip_before_action :verify_authenticity_token, only: []

  def landing
    if user_signed_in?
      redirect_to dashboard_apps_path
    else
      render layout: "landing"
    end
  end

  def pricing
    if Wokku.ee? && defined?(DynoTier)
      @dyno_tiers = DynoTier.order(:price_cents_per_hour)
      @service_tiers = ServiceTier.available.order(:service_type, :price_cents_per_hour)
    end
  end

  def docs
  end
end

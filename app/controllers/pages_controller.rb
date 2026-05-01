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
    @container_tiers = ServiceTier.available.for_type("container").order(:price_cents_per_hour)
    @database_tiers = ServiceTier.available.for_type("database").order(:price_cents_per_hour)
    render layout: "landing"
  end

  def deploy
    render layout: "landing"
  end

  def privacy
    render layout: "landing"
  end

  def terms
    render layout: "landing"
  end

  def faq
    render layout: "landing"
  end

  def refund
    render layout: "landing"
  end
end

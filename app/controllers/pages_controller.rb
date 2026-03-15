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
    @plans = Wokku.ee? && defined?(Plan) ? Plan.order(:price_cents_per_month) : []
  end

  def docs
  end
end

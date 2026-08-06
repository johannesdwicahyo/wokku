class VitalsIngestController < ActionController::API
  # Public, browser-originated. No session, no CSRF, no auth.
  # Rate-limited per-token via Rack::Attack throttle (see initializers/rack_attack.rb).

  def create
    app = AppRecord.where.not(vitals_ingest_token: nil)
                   .find_by(vitals_ingest_token: params[:t].to_s)
    return head :not_found unless app

    metric = params[:metric].to_s
    value  = Float(params[:value]) rescue nil
    return head :unprocessable_entity unless VitalsEvent::METRICS.include?(metric)
    return head :unprocessable_entity if value.nil? || value.negative? || !value.finite?

    VitalsEvent.create!(app_record: app, metric: metric, value_ms: value)
    head :no_content
  end
end

# Wake-on-request endpoint. A sleeping app's vhosts are proxied here by
# Caddy (URI rewritten to /__wake/<token>). Starts the app once per burst
# and answers 503 + Retry-After — a self-refreshing page for browsers, so
# the refresh lands on the app once its route flips back.
class WakeController < ActionController::Base
  skip_forgery_protection

  RETRY_AFTER = 5

  def show
    app = AppRecord.find_by_wake_token(params[:token])
    return head :not_found unless app

    response.headers["Cache-Control"] = "no-store"
    html = request.accepts.any? { |t| t.to_s == "text/html" } || request.format.html?
    # A billing-suspended paid app shares status: sleeping; an old token must
    # not promise it is waking (WakeAppJob would no-op anyway).
    unless app.sleeping_tier?
      return html ? render(html: paused_page(app.name), status: :service_unavailable) : render(plain: "app unavailable", status: :service_unavailable)
    end

    if app.sleeping? && Rails.cache.write("wake:#{app.id}", 1, unless_exist: true, expires_in: 2.minutes)
      WakeAppJob.perform_later(app.id)
    end

    response.headers["Retry-After"] = RETRY_AFTER.to_s
    if html
      render html: waking_page(app.name), status: :service_unavailable
    else
      render plain: "waking up, retry in #{RETRY_AFTER}s", status: :service_unavailable
    end
  end

  private

  def paused_page(name)
    <<~HTML.html_safe
      <!doctype html><html lang="en"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>#{ERB::Util.h(name)} is paused</title>
      <style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#F6F6F5;color:#171717}main{text-align:center;padding:2rem}h1{font-size:1.5rem}p{color:#3F3F3F}</style>
      </head><body><main><h1>#{ERB::Util.h(name)} is paused</h1>
      <p>This app is currently unavailable. If it’s yours, check your Wokku dashboard.</p></main></body></html>
    HTML
  end

  def waking_page(name)
    <<~HTML.html_safe
      <!doctype html><html lang="en"><head><meta charset="utf-8">
      <meta http-equiv="refresh" content="#{RETRY_AFTER}">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Waking up #{ERB::Util.h(name)}…</title>
      <style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#F6F6F5;color:#171717}main{text-align:center;padding:2rem}h1{font-size:1.5rem}p{color:#3F3F3F}</style>
      </head><body><main><h1>Waking up #{ERB::Util.h(name)}…</h1>
      <p>This free app was asleep. It’ll be ready in a few seconds — this page refreshes on its own.</p></main></body></html>
    HTML
  end
end

# Control-plane maintenance gate.
#
# Flip `MAINTENANCE_MODE=true` (via `kamal env push`) to lock the
# wokku.cloud dashboard / API behind a static "we're upgrading" page.
#
# **Important scope:** this gate only sits in front of the Rails control
# plane. User-deployed apps run on Dokku hosts and are NOT affected — they
# keep serving traffic during the maintenance window.
#
# Bypasses:
#   * `/up` Rails health check (so Kamal still reports OK)
#   * `/assets`, `/packs`, `/favicon.ico`, `/robots.txt` (so the page can render
#     and admin sign-in pages can load)
#   * Devise sign-in/out routes (so admins can authenticate during maintenance)
#   * Any request from a signed-in **admin** user (Warden session)
class MaintenanceGate
  ALLOWED_PATH_PREFIXES = %w[
    /up
    /healthz
    /assets
    /packs
    /favicon.ico
    /robots.txt
    /users/sign_in
    /users/sign_out
    /users/password
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless maintenance_on?
    return @app.call(env) if path_allowed?(env)
    return @app.call(env) if admin_user?(env)

    static_maintenance_response(env)
  end

  private

  def maintenance_on?
    ENV["MAINTENANCE_MODE"].to_s.downcase.in?(%w[1 true yes on])
  end

  def path_allowed?(env)
    path = env["PATH_INFO"].to_s
    ALLOWED_PATH_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
  end

  def admin_user?(env)
    warden = env["warden"]
    return false unless warden
    user = warden.user(:user) rescue nil
    user&.respond_to?(:admin?) && user.admin?
  end

  def static_maintenance_response(env)
    locale = env["HTTP_ACCEPT_LANGUAGE"].to_s.start_with?("id") ? :id : :en
    body = render_html(locale)
    [
      503,
      {
        "Content-Type"  => "text/html; charset=utf-8",
        "Content-Length" => body.bytesize.to_s,
        "Retry-After"   => "3600",
        "Cache-Control" => "no-store"
      },
      [ body ]
    ]
  end

  def render_html(locale)
    if locale == :id
      title    = "Wokku sedang upgrade"
      headline = "Kami sedang upgrade."
      sub      = "Sebentar lagi balik. Coba refresh dalam beberapa menit."
      note     = "App yang sudah ter-deploy tetap jalan normal — yang lagi maintenance cuma dashboard control plane."
    else
      title    = "Wokku is upgrading"
      headline = "We're upgrading."
      sub      = "Back shortly. Try refreshing in a few minutes."
      note     = "Apps you've already deployed keep serving traffic — only the control-plane dashboard is paused."
    end

    <<~HTML
      <!doctype html>
      <html lang="#{locale}">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{title}</title>
          <style>
            :root { --ink: #0c0c0e; --paper: #faf9f5; --accent: #ff5a1f; }
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; }
            body {
              background: var(--paper); color: var(--ink);
              font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Inter", sans-serif;
              min-height: 100vh;
              display: grid; place-items: center;
              padding: 32px 20px;
            }
            .panel {
              max-width: 580px; width: 100%;
              border: 1.5px solid var(--ink);
              background: var(--paper);
              padding: 36px 28px;
              box-shadow: 6px 6px 0 var(--ink);
            }
            .eyebrow {
              font-family: ui-monospace, "JetBrains Mono", monospace;
              font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase;
              color: var(--accent);
              margin-bottom: 16px;
            }
            h1 {
              font-size: 38px; line-height: 1.02; font-weight: 800;
              letter-spacing: -0.02em; margin: 0 0 14px;
            }
            p { font-size: 15px; line-height: 1.5; margin: 0 0 10px; color: var(--ink); }
            p.note {
              font-size: 13px; color: #555; margin-top: 18px;
              padding-top: 14px; border-top: 1px solid #d8d6cf;
            }
          </style>
        </head>
        <body>
          <main class="panel">
            <div class="eyebrow">// maintenance</div>
            <h1>#{headline}</h1>
            <p>#{sub}</p>
            <p class="note">#{note}</p>
          </main>
        </body>
      </html>
    HTML
  end
end

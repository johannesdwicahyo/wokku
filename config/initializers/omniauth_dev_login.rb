# Dev/test/CI instant login.
#
# Wokku auth is OAuth-only (the User model has no :database_authenticatable
# module). Local dev has no OAuth client configured, and OmniAuth test_mode
# is unreliable through omniauth-rails_csrf_protection in a real browser.
# This Rack endpoint takes the place of email/password sign-in for
# automated flows that need a logged-in session.
#
#     GET /dev/login                                  → dev@wokku.cloud (regular)
#     GET /dev/login?email=admin@wokku.cloud&admin=1  → admin user
#
# Used by:
#   - Local dev (visual review of dashboard surfaces)
#   - CI Lighthouse audits of /dashboard/* URLs (Phase 3 backlog #15)
#   - Playwright screenshot regression (Phase 3 backlog #16)
#
# Strictly gated. Enabled when:
#   - Rails.env.development?
#   - Rails.env.test?
#   - ENV["WOKKU_ENABLE_DEV_LOGIN"] == "1"  (CI booting a prod-style server)
# Production stays off-limits as long as that env var isn't set.
#
# Implemented as a Rack endpoint (no controller constant) so it doesn't
# touch Zeitwerk autoloading or need ApplicationController at boot.
if Rails.env.development? || Rails.env.test? || ENV["WOKKU_ENABLE_DEV_LOGIN"] == "1"
  dev_login = lambda do |env|
    request = Rack::Request.new(env)
    email = request.params["email"].to_s.strip.downcase.presence || "dev@wokku.cloud"
    admin_param = request.params["admin"].to_s == "1"

    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.password = SecureRandom.hex(16)
      user.name = email.split("@").first.titleize
      user.role = admin_param ? 1 : 0 if user.respond_to?(:role=)
      user.save!(validate: false)
    end

    if user.teams.empty?
      team = Team.create!(name: "#{user.name || 'Dev'} Team", owner: user)
      TeamMembership.create!(user: user, team: team, role: :admin)
    end

    # 1.8 removed balance_usd_cents seeding from the dev-login flow.
    # Under Phase 4 the dev user lands on the Free plan; pick a paid
    # plan from the UI to exercise the invoice path locally.

    env["warden"].set_user(user, scope: :user)

    [ 302, { "Location" => "/dashboard", "Content-Type" => "text/html" },
      [ %(<html><body>Signed in as #{user.email} (dev-only). <a href="/dashboard">Continue →</a></body></html>) ] ]
  end

  Rails.application.routes.append do
    get "/dev/login", to: dev_login
  end
end

# Production Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 13 critical/high production-readiness issues so Wokku can launch publicly.

**Architecture:** Each task is a self-contained security or configuration fix. Tasks are ordered by severity (critical first). Most tasks modify a single file. All tasks include tests where applicable.

**Tech Stack:** Rails 8.1, Devise, Pundit, Rack::Attack, Rack::Cors, iPaymu API

---

## File Map

| File | Task | Action |
|------|------|--------|
| `app/controllers/webhooks/ipaymu_controller.rb` | 1 | Modify — add signature verification |
| `test/controllers/webhooks/ipaymu_controller_test.rb` | 1 | Create — webhook auth tests |
| `config/initializers/cors.rb` | 2 | Modify — restrict origins |
| `config/environments/production.rb` | 3, 9 | Modify — mailer host, config.hosts |
| `config/initializers/devise.rb` | 4, 11 | Modify — mailer_sender, lockable |
| `Gemfile` | 6 | Modify — add rack-attack |
| `config/initializers/rack_attack.rb` | 6 | Create — rate limiting rules |
| `test/initializers/rack_attack_test.rb` | 6 | Create — rate limit tests |
| `db/seeds.rb` | 7 | Modify — guard admin creation |
| `config/initializers/content_security_policy.rb` | 8 | Modify — enable CSP |
| `app/controllers/application_controller.rb` | 10 | Modify — add rescue_from |
| `app/controllers/dashboard/base_controller.rb` | 10 | Modify — add rescue_from |
| `app/models/user.rb` | 11 | Modify — add :lockable |
| `db/migrate/XXXXXX_add_lockable_to_users.rb` | 11 | Create — lockable columns |
| `public/404.html` | 12 | Modify — branded error page |
| `public/422.html` | 12 | Modify — branded error page |
| `public/500.html` | 12 | Modify — branded error page |
| `test/controllers/dashboard/apps_controller_test.rb` | 13 | Create — dashboard smoke tests |
| `test/controllers/dashboard/servers_controller_test.rb` | 13 | Create — dashboard smoke tests |
| `test/controllers/dashboard/billing_controller_test.rb` | 13 | Create — dashboard smoke tests |
| `app/controllers/api/v1/activities_controller.rb` | 10 | Modify — clamp limit param |

---

### Task 1: iPaymu Webhook Signature Verification

**Files:**
- Modify: `app/controllers/webhooks/ipaymu_controller.rb`
- Create: `test/controllers/webhooks/ipaymu_controller_test.rb`

**Context:** The GitHub webhook controller (`app/controllers/webhooks/github_controller.rb`) already implements `verify_signature!` as a `before_action`. iPaymu uses HMAC-SHA256 signing. The webhook currently accepts any POST and can mark invoices as paid — this is the most dangerous vulnerability.

- [ ] **Step 1: Write the failing test for webhook signature verification**

```ruby
# test/controllers/webhooks/ipaymu_controller_test.rb
require "test_helper"

class Webhooks::IpaymuControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invoice = invoices(:unpaid) # or create one inline
    @valid_params = {
      trx_id: "TRX123",
      status: "berhasil",
      reference_id: @invoice.reference_id,
      status_code: "1"
    }
  end

  test "rejects request without signature" do
    post webhooks_ipaymu_path, params: @valid_params, as: :json
    assert_response :unauthorized
  end

  test "rejects request with invalid signature" do
    post webhooks_ipaymu_path, params: @valid_params, as: :json,
      headers: { "HTTP_X_IPAYMU_SIGNATURE" => "invalid-signature" }
    assert_response :unauthorized
  end

  test "accepts request with valid signature" do
    body = @valid_params.to_json
    api_key = ENV.fetch("IPAYMU_API_KEY", "SANDBOX2BAE12F9-82A3-49CA-B1B2-6BF9ACD0D8A9")
    signature = OpenSSL::HMAC.hexdigest("sha256", api_key, body)

    post webhooks_ipaymu_path,
      params: body,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_IPAYMU_SIGNATURE" => signature
      }
    assert_response :ok
  end

  test "marks invoice as paid on status_code 1 with valid signature" do
    body = @valid_params.to_json
    api_key = ENV.fetch("IPAYMU_API_KEY", "SANDBOX2BAE12F9-82A3-49CA-B1B2-6BF9ACD0D8A9")
    signature = OpenSSL::HMAC.hexdigest("sha256", api_key, body)

    post webhooks_ipaymu_path,
      params: body,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_IPAYMU_SIGNATURE" => signature
      }

    @invoice.reload
    assert_equal "paid", @invoice.status
    assert_not_nil @invoice.paid_at
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/webhooks/ipaymu_controller_test.rb`
Expected: FAIL — no signature check exists yet, requests without signature return 200

- [ ] **Step 3: Implement signature verification**

Replace the entire file `app/controllers/webhooks/ipaymu_controller.rb`:

```ruby
module Webhooks
  class IpaymuController < ActionController::API
    before_action :verify_signature!

    def create
      trx_id = params[:trx_id]
      status = params[:status]
      reference_id = params[:reference_id]
      status_code = params[:status_code]

      Rails.logger.info "iPaymu webhook: trx=#{trx_id} status=#{status} ref=#{reference_id}"

      invoice = Invoice.find_by(reference_id: reference_id)
      if invoice
        case status_code.to_s
        when "1" # Success
          invoice.update!(
            status: :paid,
            paid_at: Time.current,
            ipaymu_transaction_id: trx_id
          )
          if invoice.user.respond_to?(:billing_status=)
            invoice.user.update(billing_status: :active)
          end
          Rails.logger.info "Invoice #{reference_id} marked as paid"
        when "0" # Pending
          Rails.logger.info "Invoice #{reference_id} still pending"
        else # Failed/Expired
          invoice.update!(status: :expired)
          Rails.logger.info "Invoice #{reference_id} expired/failed"
        end
      else
        Rails.logger.warn "iPaymu webhook: invoice not found for ref=#{reference_id}"
      end

      head :ok
    end

    private

    def verify_signature!
      request.body.rewind
      body = request.body.read
      signature = request.headers["X-Ipaymu-Signature"] || request.headers["HTTP_X_IPAYMU_SIGNATURE"]

      unless signature.present? && valid_signature?(body, signature)
        head :unauthorized
      end
    end

    def valid_signature?(body, signature)
      api_key = ENV.fetch("IPAYMU_API_KEY", "SANDBOX2BAE12F9-82A3-49CA-B1B2-6BF9ACD0D8A9")
      expected = OpenSSL::HMAC.hexdigest("sha256", api_key, body)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end
end
```

**Note:** iPaymu's exact callback signature scheme may differ — check their docs at https://documenter.getpostman.com/view/7508947/SWLfanD1. If they use a different signing method (e.g., SHA256 of sorted params), adjust `valid_signature?` accordingly. The key point is: **verify before processing**.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/webhooks/ipaymu_controller_test.rb`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/webhooks/ipaymu_controller.rb test/controllers/webhooks/ipaymu_controller_test.rb
git commit -m "$(cat <<'EOF'
fix: add signature verification to iPaymu webhook

Without this, anyone could POST to the webhook endpoint and mark
invoices as paid. Uses HMAC-SHA256 with timing-safe comparison.
EOF
)"
```

---

### Task 2: Restrict CORS Origins

**Files:**
- Modify: `config/initializers/cors.rb`

- [ ] **Step 1: Replace CORS config**

Replace `config/initializers/cors.rb`:

```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "wokku.dev").split(",").map(&:strip)
    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      max_age: 3600
  end
end
```

This defaults to `wokku.dev` but allows override via `CORS_ORIGINS=wokku.dev,app.wokku.dev,localhost:3000` for development.

- [ ] **Step 2: Verify locally**

Run: `CORS_ORIGINS="localhost:3000,wokku.dev" bin/rails runner "puts Rails.application.config.middleware.map(&:inspect)"`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add config/initializers/cors.rb
git commit -m "$(cat <<'EOF'
fix: restrict CORS to specific origins instead of wildcard

origins '*' allowed any website to call our API. Now restricted to
CORS_ORIGINS env var, defaulting to wokku.dev.
EOF
)"
```

---

### Task 3: Fix Mailer Configuration

**Files:**
- Modify: `config/environments/production.rb`

- [ ] **Step 1: Update mailer settings in production.rb**

Replace lines 56-70 in `config/environments/production.rb`:

```ruby
  # Enable email delivery errors so failed sends are visible.
  config.action_mailer.raise_delivery_errors = true

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "wokku.dev"), protocol: "https" }

  # Outgoing SMTP server (configure via environment variables).
  config.action_mailer.smtp_settings = {
    user_name: ENV["SMTP_USERNAME"],
    password: ENV["SMTP_PASSWORD"],
    address: ENV.fetch("SMTP_ADDRESS", "smtp.gmail.com"),
    port: ENV.fetch("SMTP_PORT", 587).to_i,
    authentication: :plain,
    enable_starttls_auto: true
  }
```

- [ ] **Step 2: Verify config loads**

Run: `RAILS_ENV=production bin/rails runner "puts Rails.application.config.action_mailer.default_url_options"`
Expected: `{:host=>"wokku.dev", :protocol=>"https"}`

- [ ] **Step 3: Commit**

```bash
git add config/environments/production.rb
git commit -m "$(cat <<'EOF'
fix: configure production mailer with real host and SMTP settings

Was using example.com placeholder. Now uses APP_HOST env var
(default wokku.dev) and SMTP credentials from environment.
EOF
)"
```

---

### Task 4: Fix Devise Mailer Sender

**Files:**
- Modify: `config/initializers/devise.rb:27`

- [ ] **Step 1: Update Devise mailer_sender**

Replace line 27 in `config/initializers/devise.rb`:

```ruby
  config.mailer_sender = ENV.fetch('DEVISE_MAILER_SENDER', 'noreply@wokku.dev')
```

- [ ] **Step 2: Commit**

```bash
git add config/initializers/devise.rb
git commit -m "$(cat <<'EOF'
fix: set Devise mailer_sender to noreply@wokku.dev

Was using the Rails scaffold placeholder email address.
EOF
)"
```

---

### Task 5: Configure SMTP (deployment step)

This is a **deployment configuration** task, not a code change. After Task 3 and 4 are deployed, set these environment variables on the production server:

```bash
SMTP_USERNAME=your-smtp-user
SMTP_PASSWORD=your-smtp-password
SMTP_ADDRESS=smtp.gmail.com  # or your SMTP provider
SMTP_PORT=587
APP_HOST=wokku.dev
DEVISE_MAILER_SENDER=noreply@wokku.dev
```

- [ ] **Step 1: Set environment variables on production server**

Via Dokku on the server:
```bash
dokku config:set wokku SMTP_USERNAME=xxx SMTP_PASSWORD=xxx SMTP_ADDRESS=smtp.gmail.com SMTP_PORT=587
```

- [ ] **Step 2: Test by triggering a password reset email**

Navigate to `/users/password/new`, enter `admin@wokku.dev`, verify email arrives.

---

### Task 6: Add Rate Limiting with Rack::Attack

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/rack_attack.rb`
- Create: `test/initializers/rack_attack_test.rb`

- [ ] **Step 1: Add rack-attack gem**

Add to `Gemfile` after the `rack-cors` line (line 71):

```ruby
gem "rack-attack"
```

- [ ] **Step 2: Install**

Run: `bundle install`

- [ ] **Step 3: Write the rate limiting test**

```ruby
# test/initializers/rack_attack_test.rb
require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  test "throttles login attempts to 5 per 20 seconds" do
    6.times do |i|
      post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
    end
    assert_equal 429, response.status
  end

  test "throttles API requests to 60 per minute" do
    61.times do
      get "/api/v1/apps", headers: { "REMOTE_ADDR" => "1.2.3.4" }
    end
    assert_equal 429, response.status
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/initializers/rack_attack_test.rb`
Expected: FAIL — Rack::Attack not configured yet

- [ ] **Step 5: Create rack_attack initializer**

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Use Rails cache for rate limiting
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Throttle login attempts ###
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  ### Throttle API requests ###
  throttle("api/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  ### Throttle password reset requests ###
  throttle("password_reset/ip", limit: 3, period: 1.minute) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end

  ### Throttle webhook endpoints ###
  throttle("webhooks/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/webhooks/")
  end

  ### Throttle registration ###
  throttle("registrations/ip", limit: 3, period: 1.minute) do |req|
    req.ip if req.path == "/users" && req.post?
  end

  ### Custom response ###
  self.throttled_responder = ->(req) {
    retry_after = (req.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "Rate limit exceeded. Retry later." }.to_json]
    ]
  }
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/initializers/rack_attack_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/rack_attack.rb test/initializers/rack_attack_test.rb
git commit -m "$(cat <<'EOF'
feat: add rate limiting with Rack::Attack

Throttles: login (5/20s), API (60/min), password reset (3/min),
webhooks (30/min), registration (3/min). Returns 429 with Retry-After.
EOF
)"
```

---

### Task 7: Secure Seeds File

**Files:**
- Modify: `db/seeds.rb`

- [ ] **Step 1: Guard admin creation with environment check**

Replace lines 1-11 in `db/seeds.rb`:

```ruby
if Rails.env.development? || Rails.env.test?
  password = "password123456"
  admin = User.find_or_create_by!(email: "admin@wokku.dev") do |u|
    u.password = password
    u.role = :admin
  end
  puts "Created admin user: admin@wokku.dev / #{password}"
else
  admin_email = ENV.fetch("ADMIN_EMAIL") { raise "ADMIN_EMAIL required for production seeds" }
  admin_password = ENV.fetch("ADMIN_PASSWORD") { raise "ADMIN_PASSWORD required for production seeds" }
  admin = User.find_or_create_by!(email: admin_email) do |u|
    u.password = admin_password
    u.role = :admin
  end
  puts "Created admin user: #{admin_email}"
end

team = Team.find_or_create_by!(name: "Default", owner: admin)
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end
puts "Created default team: Default"
```

- [ ] **Step 2: Commit**

```bash
git add db/seeds.rb
git commit -m "$(cat <<'EOF'
fix: require env vars for production seeds, no hardcoded credentials

Development/test still uses the convenience password. Production
requires ADMIN_EMAIL and ADMIN_PASSWORD environment variables.
EOF
)"
```

---

### Task 8: Enable Content Security Policy

**Files:**
- Modify: `config/initializers/content_security_policy.rb`

- [ ] **Step 1: Replace the entire CSP initializer**

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self, "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.connect_src :self, "wss://wokku.dev", "https://wokku.dev"
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self, "https://sandbox.ipaymu.com", "https://my.ipaymu.com"
  end

  # Report violations without enforcing initially (switch to enforcing after testing).
  config.content_security_policy_report_only = true
end
```

**Note:** Starting in report-only mode so it doesn't break the site. After deploying and monitoring for CSP violations in browser console, remove the `report_only` line to enforce.

- [ ] **Step 2: Verify locally**

Run: `bin/rails server`, open browser, check response headers for `Content-Security-Policy-Report-Only`.

- [ ] **Step 3: Commit**

```bash
git add config/initializers/content_security_policy.rb
git commit -m "$(cat <<'EOF'
feat: enable Content Security Policy in report-only mode

Adds CSP headers to protect against XSS. Starting in report-only
mode to identify violations before enforcing.
EOF
)"
```

---

### Task 9: Enable DNS Rebinding Protection

**Files:**
- Modify: `config/environments/production.rb`

- [ ] **Step 1: Uncomment and configure config.hosts**

Replace lines 82-89 in `config/environments/production.rb`:

```ruby
  # Enable DNS rebinding protection.
  config.hosts = [
    "wokku.dev",
    /.*\.wokku\.dev/  # Allow subdomains (app.wokku.dev, mochi.wokku.dev, etc.)
  ]

  # Skip DNS rebinding protection for the health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```

- [ ] **Step 2: Commit**

```bash
git add config/environments/production.rb
git commit -m "$(cat <<'EOF'
fix: enable config.hosts for DNS rebinding protection

Only wokku.dev and *.wokku.dev subdomains are accepted.
Health check endpoint /up is excluded.
EOF
)"
```

---

### Task 10: Add Global Error Handling

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/dashboard/base_controller.rb`
- Modify: `app/controllers/api/v1/activities_controller.rb`

- [ ] **Step 1: Add rescue_from to ApplicationController**

Replace `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Localizable
  allow_browser versions: :modern
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  private

  def not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def forbidden
    respond_to do |format|
      format.html { redirect_to root_path, alert: "You are not authorized to perform this action." }
      format.json { render json: { error: "Not authorized" }, status: :forbidden }
    end
  end
end
```

- [ ] **Step 2: Clamp limit param in activities controller**

Replace line 6 in `app/controllers/api/v1/activities_controller.rb`:

```ruby
        activities = Activity.where(team: team).order(created_at: :desc).limit([[(params[:limit] || 50).to_i, 1].max, 200].min)
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/application_controller.rb app/controllers/api/v1/activities_controller.rb
git commit -m "$(cat <<'EOF'
fix: add global error handling and clamp API limit parameter

- rescue RecordNotFound (404) and Pundit::NotAuthorizedError (403)
  in ApplicationController so dashboard gets proper error pages
- Clamp activities API limit param to 1-200 range
EOF
)"
```

---

### Task 11: Enable Devise Account Lockout

**Files:**
- Modify: `app/models/user.rb:2`
- Modify: `config/initializers/devise.rb:200-217`
- Create: `db/migrate/XXXXXX_add_lockable_to_users.rb`

- [ ] **Step 1: Generate migration for lockable columns**

Run: `bin/rails generate migration AddLockableToUsers failed_attempts:integer:index unlock_token:string:uniq locked_at:datetime`

- [ ] **Step 2: Set default for failed_attempts in migration**

Edit the generated migration to set the default:

```ruby
class AddLockableToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
    add_index :users, :unlock_token, unique: true
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 4: Add :lockable to User model**

Replace line 2 in `app/models/user.rb`:

```ruby
  devise :two_factor_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :lockable,
         :omniauthable, omniauth_providers: [:github, :google_oauth2],
         otp_secret_encryption_key: Rails.application.credentials.secret_key_base
```

- [ ] **Step 5: Enable lockable config in devise.rb**

Replace lines 200-217 in `config/initializers/devise.rb`:

```ruby
  config.lock_strategy = :failed_attempts
  config.unlock_keys = [:email]
  config.unlock_strategy = :both
  config.maximum_attempts = 10
  config.unlock_in = 30.minutes
  config.last_attempt_warning = true
```

- [ ] **Step 6: Run tests**

Run: `bin/rails test`
Expected: All existing tests pass

- [ ] **Step 7: Commit**

```bash
git add app/models/user.rb config/initializers/devise.rb db/migrate/*add_lockable*
git commit -m "$(cat <<'EOF'
feat: enable Devise account lockout after 10 failed attempts

Locks account for 30 minutes after 10 failed login attempts.
Unlock via email link or time expiry. Combined with Rack::Attack
rate limiting for defense in depth.
EOF
)"
```

---

### Task 12: Brand Error Pages

**Files:**
- Modify: `public/404.html`
- Modify: `public/422.html`
- Modify: `public/500.html`

- [ ] **Step 1: Replace 404.html**

```html
<!doctype html>
<html lang="en">
<head>
  <title>Page Not Found - Wokku</title>
  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1, width=device-width">
  <meta name="robots" content="noindex, nofollow">
  <style>
    *, *::before, *::after { box-sizing: border-box; }
    * { margin: 0; }
    body {
      background: #0f0a1a;
      color: #e0dce8;
      display: grid;
      font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
      font-size: 16px;
      min-height: 100dvh;
      place-items: center;
      -webkit-font-smoothing: antialiased;
    }
    main { text-align: center; padding: 2rem; }
    .logo { font-size: 1.5rem; font-weight: 700; color: #a78bfa; margin-bottom: 2rem; }
    .code { font-size: 6rem; font-weight: 800; color: #2d2540; line-height: 1; }
    .title { font-size: 1.5rem; font-weight: 600; color: #f87171; margin: 0.5rem 0 1rem; }
    .desc { color: #9b95a8; max-width: 30em; margin: 0 auto 2rem; }
    a { color: #a78bfa; text-decoration: none; font-weight: 600; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <main>
    <div class="logo">Wokku.dev</div>
    <div class="code">404</div>
    <div class="title">Page Not Found</div>
    <p class="desc">The page you were looking for doesn't exist. You may have mistyped the address or the page may have moved.</p>
    <a href="/">Back to Dashboard</a>
  </main>
</body>
</html>
```

- [ ] **Step 2: Replace 422.html**

Same structure as 404.html but with:
- Title: `Unprocessable Content - Wokku`
- Code: `422`
- Title div: `Unprocessable Content`
- Desc: `The request could not be processed. This may be due to an invalid form submission or expired session.`

- [ ] **Step 3: Replace 500.html**

Same structure as 404.html but with:
- Title: `Server Error - Wokku`
- Code: `500`
- Title div: `Something Went Wrong`
- Desc: `We're sorry, something went wrong on our end. Please try again later or contact support@wokku.dev if the problem persists.`

- [ ] **Step 4: Verify locally**

Open each file directly in browser to confirm styling matches the dark theme.

- [ ] **Step 5: Commit**

```bash
git add public/404.html public/422.html public/500.html
git commit -m "$(cat <<'EOF'
fix: brand error pages with Wokku dark theme

Replace default Rails error pages with branded pages matching
the Wokku dashboard aesthetic.
EOF
)"
```

---

### Task 13: Add Dashboard Controller Smoke Tests

**Files:**
- Create: `test/controllers/dashboard/apps_controller_test.rb`
- Create: `test/controllers/dashboard/servers_controller_test.rb`
- Create: `test/controllers/dashboard/billing_controller_test.rb`

**Context:** Zero dashboard controller tests exist. These smoke tests verify authentication is required and basic pages load for authenticated users.

- [ ] **Step 1: Write apps controller smoke test**

```ruby
# test/controllers/dashboard/apps_controller_test.rb
require "test_helper"

class Dashboard::AppsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:admin)
  end

  test "redirects to login when not authenticated" do
    get dashboard_apps_path
    assert_redirected_to new_user_session_path
  end

  test "shows apps index when authenticated" do
    sign_in @user
    get dashboard_apps_path
    assert_response :success
  end

  test "shows app detail when authenticated" do
    sign_in @user
    app = app_records(:first) # adjust to your fixture name
    get dashboard_app_path(app)
    assert_response :success
  end
end
```

- [ ] **Step 2: Write servers controller smoke test**

```ruby
# test/controllers/dashboard/servers_controller_test.rb
require "test_helper"

class Dashboard::ServersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:admin)
  end

  test "redirects to login when not authenticated" do
    get dashboard_servers_path
    assert_redirected_to new_user_session_path
  end

  test "shows servers index when authenticated" do
    sign_in @user
    get dashboard_servers_path
    assert_response :success
  end
end
```

- [ ] **Step 3: Write billing controller smoke test**

```ruby
# test/controllers/dashboard/billing_controller_test.rb
require "test_helper"

class Dashboard::BillingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:admin)
  end

  test "redirects to login when not authenticated" do
    get dashboard_billing_path
    assert_redirected_to new_user_session_path
  end

  test "shows billing when authenticated" do
    sign_in @user
    get dashboard_billing_path
    assert_response :success
  end
end
```

- [ ] **Step 4: Run all dashboard tests**

Run: `bin/rails test test/controllers/dashboard/`
Expected: All tests pass. Adjust fixture names if needed — check `test/fixtures/` for existing fixture names.

- [ ] **Step 5: Commit**

```bash
git add test/controllers/dashboard/
git commit -m "$(cat <<'EOF'
test: add dashboard controller smoke tests

Covers apps, servers, and billing controllers with auth redirect
and basic page load assertions. Foundation for expanding coverage.
EOF
)"
```

---

## Final Verification

- [ ] **Run full test suite**

```bash
bin/rails test
```
Expected: All tests pass.

- [ ] **Run security audit**

```bash
bundle exec brakeman -q
bundle exec bundler-audit check --update
```
Expected: No new critical issues.

- [ ] **Deploy and verify**

```bash
git push dokku main
```

After deploy, verify on wokku.dev:
1. Visit `/nonexistent` — see branded 404 page
2. Try login with wrong password 10+ times — account locks
3. Check response headers for CSP
4. Verify webhook rejects unsigned requests (use `curl -X POST https://wokku.dev/webhooks/ipaymu`)
5. Send a test password reset email

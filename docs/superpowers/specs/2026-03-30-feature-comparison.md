# Wokku vs Coolify vs Heroku — Feature Comparison (Audit: 2026-03-30)

> **Legend:**
> - **W** = Works end-to-end (tested/verified in codebase)
> - **P** = Partial (code exists but incomplete, buggy, or not wired to UI)
> - **X** = Not implemented
> - **N/A** = Not applicable to that platform

---

## 1. DEPLOYMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Git push deploy | **X** (stub — server closes connection immediately) | **X** | **W** (via SSH) | **W** |
| GitHub webhook auto-deploy | **W** | **W** | **W** (GitHub App) | **W** |
| GitLab integration | **X** | **X** | **W** (deploy key + webhook) | **W** (via add-on) |
| Bitbucket integration | **X** | **X** | **W** (deploy key + webhook) | **W** |
| Dockerfile deploy | **P** (Dokku auto-detects, no UI) | **P** | **W** (first-class) | **W** (heroku.yml) |
| Docker Compose deploy | **P** (templates only, not arbitrary) | **P** | **W** (first-class) | **X** |
| Docker image deploy | **W** (via templates, `git:from-image`) | **W** | **W** | **W** (container registry) |
| Buildpacks | **P** (Dokku auto-detects, no UI to configure) | **P** | **X** (uses Nixpacks instead) | **W** (first-class) |
| Nixpacks | **X** | **X** | **W** (default builder) | **X** |
| One-click templates | **W** (50+ templates from docker-compose) | **W** | **W** (200+ curated services) | **W** (Heroku Buttons) |
| PR preview deployments | **W** (creates app, copies env, comments on PR) | **W** | **W** (GitHub only) | **W** (Review Apps) |
| CI/CD pipelines | **X** | **X** | **P** (webhook triggers) | **W** (Heroku CI + Pipelines) |
| Rollback | **X** (API exists but creates orphan record, no actual deploy) | **X** | **X** | **W** (one-click) |
| Deploy from branch selection | **W** (stored on app record) | **W** | **W** | **W** |
| Static site deploy | **X** | **X** | **W** (static buildpack) | **W** (via buildpack) |
| Monorepo support | **X** | **X** | **P** (base directory setting) | **X** |

---

## 2. APP MANAGEMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Create app | **W** | **W** | **W** | **W** |
| Start / Stop / Restart | **W** (calls `ps:start/stop/restart`) | **W** | **W** | **W** |
| Destroy app | **W** (calls `apps:destroy --force`) | **W** | **W** | **W** |
| Environment variables (CRUD) | **W** (encrypted at rest, syncs with Dokku) | **W** | **W** (build vs runtime separation) | **W** |
| Custom domains | **W** (calls `domains:add/remove`) | **W** | **W** | **W** |
| SSL / Let's Encrypt | **W** (auto via `letsencrypt:enable`) | **W** | **W** (automatic) | **W** (ACM) |
| Wildcard domains | **X** | **X** | **W** (server-level) | **X** |
| Wildcard SSL | **X** | **X** | **W** | **X** |
| Force HTTPS redirect | **X** | **X** | **W** | **W** |
| App maintenance mode | **X** | **X** | **X** | **W** |

---

## 3. SCALING & RESOURCES

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Horizontal scaling (process count) | **W** (calls `ps:scale`) | **W** | **W** (multi-server) | **W** |
| Vertical scaling (dyno/container size) | **X** | **P** (service exists, `resource:limit` works via CLI, **NO UI to choose tier**) | **W** (CPU/memory per container) | **W** (dyno types) |
| Resource limits (memory) | **X** | **P** (applied via rake task, **UI shows "No limits" due to key mismatch bug**) | **W** | **W** |
| Resource limits (CPU) | **X** | **P** (same issue as memory) | **W** | **W** |
| Auto-scaling | **X** | **X** | **X** | **W** (Performance dynos) |
| Dyno tier selection UI | **X** | **X** (model + API exist, **no dashboard UI**) | **W** (per-container config) | **W** |
| Process type management | **W** (web, worker via Procfile) | **W** | **W** | **W** |
| Docker Swarm clustering | **X** | **X** | **W** | N/A |
| Kubernetes | **X** | **X** | **X** (planned) | **W** (Private Spaces) |

---

## 4. DATABASE SERVICES

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| PostgreSQL | **W** (Dokku plugin) | **W** | **W** (one-click) | **W** (Heroku Postgres) |
| MySQL | **W** | **W** | **W** | **W** (ClearDB/JawsDB) |
| MariaDB | **W** | **W** | **W** | **P** (add-on) |
| MongoDB | **W** | **W** | **W** | **W** (mLab/ObjectRocket) |
| Redis | **W** | **W** | **W** | **W** (Heroku Data for Redis) |
| Memcached | **W** (listed in SUPPORTED_TYPES) | **W** | **P** (via Docker) | **W** (MemCachier) |
| RabbitMQ | **W** (listed) | **W** | **P** (via Docker/template) | **W** (CloudAMQP) |
| Elasticsearch | **W** (listed) | **W** | **P** (via Docker) | **W** (Bonsai) |
| MinIO (S3-compatible) | **W** (listed) | **W** | **P** (via Docker) | **X** |
| KeyDB | **X** | **X** | **W** (one-click) | **X** |
| ClickHouse | **X** | **X** | **W** (one-click) | **X** |
| Database linking to apps | **W** (calls `service:link`) | **W** | **W** (env injection) | **W** (add-on attachment) |
| Database credentials UI | **W** (shows connection string) | **W** | **W** | **W** |
| Database backups | **W** (S3-compatible, cron schedule) | **W** | **W** (S3-compatible, cron) | **W** (continuous + snapshots) |
| Database backup restore | **W** (download + import) | **W** | **W** (one-click) | **W** |
| Backup for memcached/rabbitmq/elasticsearch | **X** (raises "Unsupported" error) | **X** | **X** | N/A |

---

## 5. MONITORING & OBSERVABILITY

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Container metrics (CPU/RAM) | **P** (requires root SSH; fails silently if unavailable) | **P** | **W** (Sentinel agent) | **W** |
| Resource limits display | **X** | **P** (controller parses Dokku output but **key names don't match view** — shows "No limits" even when set) | **W** | **W** |
| Historical metrics (charts) | **P** (Chartkick graphs exist, but `MetricsPollJob` needs scheduler) | **P** | **P** (CPU/RAM only) | **W** (full APM with throughput, latency, errors) |
| Real-time log streaming | **P** (LogChannel exists but fetch-based, not true streaming) | **P** | **W** | **W** |
| Log fetch (recent lines) | **W** (200 lines via `logs:failed` / Dokku logs) | **W** | **W** | **W** |
| Log aggregation / search | **X** | **X** | **X** (deploy Loki) | **W** (Papertrail/Logplex) |
| Request-level metrics (RPM, latency) | **X** | **X** | **X** | **W** |
| Error tracking / APM | **X** | **X** | **X** | **W** (New Relic, Scout) |
| Health checks | **W** (HealthCheckJob exists) | **W** | **W** | **W** |
| Uptime monitoring | **X** | **X** | **X** (deploy Uptime Kuma) | **X** (add-on) |
| Disk usage alerts | **X** | **X** | **W** | **X** |

---

## 6. SERVER MANAGEMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Multi-server support | **W** (add multiple Dokku servers) | **W** | **W** (unlimited) | N/A (managed) |
| Server provisioning (cloud API) | **W** (Hetzner, Vultr via CloudProvider) | **W** | **W** (Hetzner, DO, AWS, etc.) | N/A |
| Add existing server (SSH) | **W** | **W** | **W** | N/A |
| Server sync (discover apps) | **W** (SyncServerJob pulls from Dokku) | **W** | **W** | N/A |
| Server status monitoring | **W** (connected/unreachable/syncing) | **W** | **W** | N/A |
| Web terminal (browser SSH) | **W** (ActionCable + PTY, 15min timeout) | **W** | **W** | **W** (heroku run bash) |
| Server capacity tracking | **X** | **W** (capacity_total_mb, capacity_used_mb) | **P** (CPU/RAM metrics) | N/A |
| Server placement / bin-packing | **X** | **W** (ServerPlacement service) | **X** | N/A |
| Docker cleanup automation | **X** | **X** | **W** | N/A |

---

## 7. NETWORKING & PROXY

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Reverse proxy | **W** (nginx via Dokku) | **W** | **W** (Traefik default, Caddy experimental) | **W** (Heroku Router) |
| Custom proxy config | **X** | **X** | **W** | **X** |
| WebSocket support | **W** (Dokku supports it) | **W** | **W** | **W** |
| Custom ports | **P** (template deployer sets ports) | **P** | **W** | **X** (web only on $PORT) |
| Private networking | **X** | **X** | **W** (Docker networks) | **W** (Private Spaces) |
| Load balancing | **X** | **X** | **P** (external LB needed) | **W** |

---

## 8. AUTHENTICATION & TEAM MANAGEMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Email/password auth | **W** (Devise) | **W** | **W** | **W** |
| GitHub OAuth | **W** (Omniauth) | **W** | **W** (GitHub App) | **W** |
| Google OAuth | **W** (Omniauth) | **W** | **X** | **W** (SSO) |
| Two-factor auth (2FA) | **X** | **X** | **W** (TOTP) | **W** |
| SSO / SAML | **X** | **X** | **X** (deploy Authentik) | **W** (Enterprise) |
| Teams | **W** (owner + members) | **W** | **W** | **W** |
| Role-based access (RBAC) | **W** (viewer/member/admin via Pundit) | **W** | **P** (rudimentary, team-level only) | **W** (fine-grained) |
| API tokens | **W** (SHA256 hashed, expiration, revocation) | **W** | **W** (Sanctum) | **W** (OAuth) |
| Audit log | **X** | **W** (Activity model, 23 action types) | **P** (operation logging) | **W** |

---

## 9. BILLING & PRICING

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Usage-based billing | N/A | **P** (ResourceUsage model works, billing calculation works, **but no automated creation of usage records on app deploy**) | N/A (self-hosted free) | **W** |
| Stripe integration | N/A | **P** (webhooks configured, StripeBilling service exists, **checkout flow unclear**) | N/A | **W** |
| Plans / subscriptions | N/A | **P** (Plan + Subscription models exist, **no stripe_price_id in schema**) | **W** ($5/mo cloud) | **W** |
| Invoices | N/A | **P** (Invoice model exists, Stripe webhook updates status) | N/A | **W** |
| Payment methods | N/A | **P** (controller + Stripe setup intent flow) | N/A | **W** |
| Free tier | N/A | **W** (eco tier, 256MB, $0) | **W** (self-hosted = free) | **W** (eco dynos) |
| Pricing page | N/A | **X** | **W** (coolify.io/pricing) | **W** |

---

## 10. NOTIFICATIONS

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Email notifications | **W** (NotificationMailer) | **W** | **W** (SMTP, Resend) | **W** |
| Slack | **W** (webhook POST) | **W** | **W** | **W** (add-on) |
| Discord | **W** (Slack-compatible format) | **W** | **W** | **X** |
| Telegram | **W** (bot API) | **W** | **W** | **X** |
| Custom webhook | **W** (generic JSON POST) | **W** | **W** | **W** (app webhooks) |
| Pushover | **X** | **X** | **W** | **X** |
| Mobile push notifications | **X** | **P** (DeviceToken model exists, **no sending code**) | **X** | **X** |
| Deploy events | **W** | **W** | **W** | **W** |
| App crash events | **W** | **W** | **W** | **W** |
| Backup events | **W** | **W** | **W** | **X** |
| Disk / resource alerts | **X** | **X** | **W** | **X** |

---

## 11. DEVELOPER EXPERIENCE

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| CLI tool | **X** | **X** | **X** | **W** (Heroku CLI) |
| REST API (v1) | **W** (comprehensive — apps, servers, DBs, config, domains, deploys, logs, templates, teams) | **W** (+ billing, dynos, AI) | **W** (full CRUD) | **W** |
| API documentation | **X** | **X** | **W** (interactive docs) | **W** |
| Dashboard UI | **W** (39 views, dark theme, Turbo SPA) | **W** (+ billing, scaling) | **W** | **W** |
| Mobile app | **X** | **P** (React Native app exists, API endpoints for templates/deploys/devices) | **X** | **X** |
| PWA | **P** (manifest valid, service worker commented out, **no offline**) | **P** | **X** | **X** |
| AI debugging | **X** | **W** (Claude API diagnoses deploy failures) | **X** | **X** |
| Docker registry | **X** | **X** | **W** (push to any registry) | **W** (Container Registry) |

---

## 12. PLATFORM INTERNALS

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Tech stack | Rails 8.1, PostgreSQL, Tailwind | Same + EE modules | Laravel, PHP, PostgreSQL | Proprietary |
| Container runtime | Dokku (Docker-based) | Dokku | Docker / Docker Swarm | Dynos (LXC-based) |
| Proxy | nginx (Dokku) | nginx (Dokku) | Traefik / Caddy | Heroku Router |
| Job queue | Solid Queue | Solid Queue | Laravel Horizon | N/A |
| Self-hosted | **W** (Kamal deploy) | **W** | **W** | **X** (managed only) |
| Open source | **W** (MIT) | Private repo | **W** (Apache 2.0) | **X** |
| Multi-language support | **P** (EN/ID in mobile) | **P** | **X** | **W** |

---

## CRITICAL BUGS FOUND IN THIS AUDIT

| # | Severity | Component | Issue |
|---|----------|-----------|-------|
| 1 | **HIGH** | Resource Limits UI | `MetricsController#fetch_resources` parses Dokku output into keys like `default_limit_memory` but view checks for `resource_limits_memory`. **Result: always shows "No resource limits configured" even when limits are set.** Fix was attempted this session but the deployed app still has the old code. |
| 2 | **HIGH** | Git Push Deploy | `Git::Server#handle_connection` is a stub that immediately closes the socket. Git push deploy is completely non-functional despite the UI showing instructions. |
| 3 | **HIGH** | Rollback | `Api::V1::ReleasesController#rollback` creates a Release record but **never triggers a deploy**. Users think rollback succeeded but nothing changes. |
| 4 | **MEDIUM** | Dyno Tier UI | No dashboard page exists to select dyno tiers. The `DynoTier` model, `DynoAllocation` model, and `ApplyDynoTierJob` all work, but there's no way for users to change tiers through the web UI. Only the API endpoint `PATCH /api/v1/apps/:id/dynos/:id` works. |
| 5 | **MEDIUM** | Container Metrics | Requires root SSH access. Fails silently with "Unable to fetch container metrics" if only dokku user SSH is configured. No error message explains the root requirement. |
| 6 | **MEDIUM** | Database Backups | `BackupService#run_streaming` mixes stdout and stderr. Large database exports could be corrupted by interleaved error messages. |
| 7 | **MEDIUM** | Billing Flow | `ResourceUsage` records are not automatically created when apps are deployed. The billing calculation works but the data input is missing. |
| 8 | **LOW** | Backup Types | Backup/restore not supported for memcached, rabbitmq, elasticsearch, minio — UI allows creating these databases but backup will raise "Unsupported database type". |
| 9 | **LOW** | Mobile Push | `DeviceToken` model stores tokens but no code sends push notifications to iOS/Android. |
| 10 | **LOW** | PWA | Service worker is entirely commented out. Can install as PWA but no offline support. |

---

## SUMMARY SCORECARD

| Category | Wokku CE | Wokku EE | Coolify | Heroku |
|----------|----------|----------|---------|--------|
| Deployment methods | 4/10 | 4/10 | 9/10 | 9/10 |
| App management | 7/10 | 7/10 | 8/10 | 10/10 |
| Scaling & resources | 3/10 | 4/10 | 7/10 | 10/10 |
| Database services | 7/10 | 7/10 | 8/10 | 9/10 |
| Monitoring | 3/10 | 3/10 | 6/10 | 9/10 |
| Server management | 7/10 | 8/10 | 8/10 | N/A |
| Auth & teams | 6/10 | 7/10 | 6/10 | 9/10 |
| Billing | 0/10 | 3/10 | N/A | 10/10 |
| Notifications | 7/10 | 7/10 | 9/10 | 5/10 |
| Developer experience | 4/10 | 5/10 | 7/10 | 10/10 |
| **Overall** | **4.8/10** | **5.5/10** | **7.5/10** | **9.0/10** |

---

## TOP PRIORITIES TO CLOSE THE GAP WITH COOLIFY

1. **Fix resource limits display** — the data is there, the view just has wrong key names
2. **Build dyno tier selection UI** — model/job/API all work, just needs a dashboard page
3. **Implement git push deploy** — critical for developer experience, the Git::Server is a stub
4. **Implement rollback** — the API creates orphan records, needs to actually trigger a deploy
5. **Fix container metrics** — either document root SSH requirement or switch to `dokku` user commands
6. **Add Dockerfile/Compose deploy UI** — Dokku supports both, Wokku just doesn't expose them
7. **Wire up billing flow** — create ResourceUsage records on deploy, verify Stripe checkout
8. **Add 2FA** — table stakes for a hosting platform

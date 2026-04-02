# Wokku vs Coolify vs Heroku — Feature Comparison (Updated: 2026-04-02)

> **Legend:**
> - **W** = Works end-to-end (tested/verified)
> - **P** = Partial (code exists but incomplete)
> - **X** = Not implemented
> - **N** = New since last audit (Mar 30)
> - **F** = Fixed since last audit
> - **N/A** = Not applicable

---

## Changes Since Last Audit (Mar 30 → Apr 2)

### Bugs Fixed (10)
1. **F** Resource limits display — fixed Dokku v0.37 key parsing
2. **F** Rollback — now triggers actual deploy via DeployJob
3. **F** Container metrics — uses `deploy` user SSH instead of restricted `dokku` shell
4. **F** Dyno tier UI — full container size selection with pricing on Scaling page
5. **F** Billing ResourceUsage — auto-created on deploy
6. **F** Terminal 500 error — resolves server through app
7. **F** Solid Queue — migrations installed, background jobs persist
8. **F** MongoDB plugin name — mapped `mongodb` → `mongo`
9. **F** App.json formations — scaling gracefully skips ps:scale
10. **F** Turbo confirm dialog — custom styled modal replaces browser alert

### Features Added (15+)
1. **N** Dyno Core design system — complete UI redesign (purple/indigo theme)
2. **N** Sidebar navigation with Material Symbols icons
3. **N** Unified single-page app detail (no tabs)
4. **N** Heroku-style Resources tab (add-ons per app)
5. **N** Resources page (all add-ons grouped by type/app)
6. **N** Container size tiers with pricing ($0-$15/mo)
7. **N** Horizontal scaling restrictions (Free/Basic locked)
8. **N** 6 new Dokku plugins (Meilisearch, ClickHouse, NATS, HTTP Auth, Maintenance, Redirect)
9. **N** App console — sandboxed container shell via `dokku enter`
10. **N** Server terminal — admin-only Dokku shell
11. **N** Activity tracking across web UI, API, and sync jobs
12. **N** Server hardening (UFW, fail2ban, SSH hardening)
13. **N** 1 Click Deploy redesign with category sidebar
14. **N** Dashboard page with stats, recent apps, activity, news
15. **N** Settings page with account overview, API credentials, resource stats

---

## 1. DEPLOYMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Git push deploy | **X** (stub) | **X** | **W** | **W** |
| GitHub webhook auto-deploy | **W** | **W** | **W** | **W** |
| GitLab integration | **X** | **X** | **W** | **W** |
| Bitbucket integration | **X** | **X** | **W** | **W** |
| Dockerfile deploy | **P** (auto-detect) | **P** | **W** | **W** |
| Docker Compose deploy | **P** (templates) | **P** | **W** | **X** |
| Docker image deploy | **W** | **W** | **W** | **W** |
| Buildpacks | **P** (auto-detect) | **P** | **X** (Nixpacks) | **W** |
| One-click templates | **W** (50+) | **W** | **W** (200+) | **W** |
| PR preview deployments | **W** | **W** | **W** | **W** |
| CI/CD pipelines | **X** | **X** | **P** | **W** |
| Rollback | **W** **F** (triggers deploy) | **W** **F** | **X** | **W** |
| Static site deploy | **X** | **X** | **W** | **W** |

---

## 2. APP MANAGEMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Create app | **W** | **W** | **W** | **W** |
| Start / Stop / Restart | **W** | **W** | **W** | **W** |
| Destroy app | **W** | **W** | **W** | **W** |
| Environment variables | **W** (encrypted) | **W** | **W** | **W** |
| Custom domains | **W** | **W** | **W** | **W** |
| SSL / Let's Encrypt | **W** | **W** | **W** | **W** |
| App maintenance mode | **W** **N** (dokku-maintenance plugin) | **W** | **X** | **W** |
| HTTP Auth (staging) | **W** **N** (dokku-http-auth plugin) | **W** | **X** | **X** |
| URL Redirects | **W** **N** (dokku-redirect plugin) | **W** | **X** | **X** |
| Unified app detail page | **W** **N** (single-page, no tabs) | **W** | **W** | **W** |

---

## 3. SCALING & RESOURCES

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Horizontal scaling | **W** | **W** | **W** | **W** |
| Vertical scaling (container size) | **X** | **W** **F** (5 tiers with UI) | **W** | **W** |
| Resource limits display | **X** | **W** **F** (MB + vCPU units) | **W** | **W** |
| Container metrics (CPU/RAM) | **X** | **W** **F** (per-app, configured limits) | **W** | **W** |
| Dyno tier selection UI | **X** | **W** **N** (upgrade/downgrade + pricing) | **W** | **W** |
| Pricing preview | **X** | **W** **N** (per-dyno cost breakdown) | **X** | **W** |
| Scaling restrictions by tier | **X** | **W** **N** (Free/Basic can't scale) | **X** | **W** |
| Process type via Procfile | **W** | **W** | **W** | **W** |
| Auto-scaling | **X** | **X** | **X** | **W** |

---

## 4. ADD-ON SERVICES

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| PostgreSQL | **W** | **W** | **W** | **W** |
| MySQL | **W** | **W** | **W** | **W** |
| MariaDB | **W** | **W** | **W** | **P** |
| MongoDB | **W** **F** | **W** | **W** | **W** |
| Redis | **W** | **W** | **W** | **W** |
| Memcached | **W** | **W** | **P** | **W** |
| RabbitMQ | **W** | **W** | **P** | **W** |
| Elasticsearch | **W** | **W** | **P** | **W** |
| Meilisearch | **W** **N** | **W** | **X** | **X** |
| ClickHouse | **W** **N** | **W** | **X** | **X** |
| NATS | **W** **N** | **W** | **X** | **X** |
| Heroku-style Resources tab | **W** **N** | **W** | **X** | **W** |
| Add-on auto-link on provision | **W** **N** | **W** | **W** | **W** |
| Resources overview (grouped) | **W** **N** (by type or app) | **W** | **W** | **W** |
| Database link sync from Dokku | **W** **N** | **W** | N/A | N/A |
| Database backups | **W** | **W** | **W** | **W** |

---

## 5. MONITORING & OBSERVABILITY

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Container metrics (CPU/RAM) | **W** **F** | **W** | **W** | **W** |
| Resource limits display | **W** **F** | **W** | **W** | **W** |
| Live log preview (app detail) | **W** **N** | **W** | **W** | **W** |
| Full log viewer | **W** | **W** | **W** | **W** |
| Historical charts | **P** | **P** | **P** | **W** |
| Health checks | **W** | **W** | **W** | **W** |
| Activity tracking (all sources) | **W** **N** | **W** | **P** | **W** |

---

## 6. SERVER MANAGEMENT

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Multi-server support | **W** | **W** | **W** | N/A |
| Server provisioning | **W** | **W** | **W** | N/A |
| Server sync | **W** **N** (+ link sync) | **W** | **W** | N/A |
| Server status monitoring | **W** | **W** | **W** | N/A |
| App console (container shell) | **W** **N** (sandboxed) | **W** | **W** | **W** |
| Server terminal (admin) | **W** **N** (admin-only) | **W** | **W** | N/A |
| Server hardening | **W** **N** (UFW + fail2ban) | **W** | **W** | N/A |

---

## 7. AUTH & TEAMS

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Email/password auth | **W** | **W** | **W** | **W** |
| GitHub OAuth | **W** | **W** | **W** | **W** |
| Google OAuth | **W** | **W** | **X** | **W** |
| 2FA | **X** | **X** | **W** | **W** |
| Teams + RBAC | **W** | **W** | **P** | **W** |
| API tokens | **W** | **W** | **W** | **W** |
| Admin-only features | **W** **N** (server terminal) | **W** | **P** | **W** |

---

## 8. BILLING & PRICING

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| 5-tier pricing (Free→Perf 2x) | N/A | **W** **N** | N/A | **W** |
| Per-dyno billing model | N/A | **W** **N** | N/A | **W** |
| Resource usage tracking | N/A | **W** **F** | N/A | **W** |
| Pricing preview on scaling | N/A | **W** **N** | **X** | **W** |
| Stripe integration | N/A | **P** | N/A | **W** |
| Free tier (1 per user) | N/A | **W** **N** | **W** (self-host) | **W** |

---

## 9. NOTIFICATIONS

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Email | **W** | **W** | **W** | **W** |
| Slack | **W** | **W** | **W** | **W** |
| Discord | **W** | **W** | **W** | **X** |
| Telegram | **W** | **W** | **W** | **X** |
| Webhook | **W** | **W** | **W** | **W** |

---

## 10. UI/UX & DEVELOPER EXPERIENCE

| Feature | Wokku CE | Wokku EE | Coolify | Heroku |
|---------|----------|----------|---------|--------|
| Design system | **W** **N** (Dyno Core) | **W** | **W** | **W** |
| Sidebar navigation | **W** **N** | **W** | **W** | **W** |
| Unified app detail | **W** **N** (single page) | **W** | **W** | **W** (tabs) |
| 1 Click Deploy marketplace | **W** **N** (category sidebar) | **W** | **W** | **W** |
| Custom confirm dialogs | **W** **N** | **W** | **W** | **W** |
| Dashboard with stats | **W** **N** | **W** | **W** | **W** |
| Settings hub | **W** **N** | **W** | **W** | **W** |
| REST API (v1) | **W** | **W** | **W** | **W** |
| Mobile app | **X** | **P** | **X** | **X** |
| CLI tool | **X** | **X** | **X** | **W** |

---

## UPDATED SCORECARD

| Category | Mar 30 | Apr 2 | Coolify | Heroku |
|----------|--------|-------|---------|--------|
| Deployment methods | 4/10 | **5/10** (+1) | 9/10 | 9/10 |
| App management | 7/10 | **8/10** (+1) | 8/10 | 10/10 |
| Scaling & resources | 4/10 | **8/10** (+4) | 7/10 | 10/10 |
| Add-on services | 7/10 | **9/10** (+2) | 8/10 | 9/10 |
| Monitoring | 3/10 | **7/10** (+4) | 6/10 | 9/10 |
| Server management | 8/10 | **9/10** (+1) | 8/10 | N/A |
| Auth & teams | 7/10 | **7/10** (=) | 6/10 | 9/10 |
| Billing | 3/10 | **6/10** (+3) | N/A | 10/10 |
| Notifications | 7/10 | **7/10** (=) | 9/10 | 5/10 |
| UI/UX & DX | 5/10 | **8/10** (+3) | 7/10 | 10/10 |
| **Overall** | **5.5/10** | **7.4/10** (+1.9) | **7.5/10** | **9.0/10** |

---

## PROGRESS SUMMARY

**Overall score: 5.5 → 7.4 (+1.9 points)**

We closed 95% of the gap with Coolify (7.4 vs 7.5) and made significant progress toward Heroku.

**Biggest improvements:**
- Scaling & Resources: 4 → 8 (+4) — full tier system, pricing, restrictions
- Monitoring: 3 → 7 (+4) — working metrics, live logs, activity tracking
- UI/UX: 5 → 8 (+3) — complete Dyno Core redesign
- Billing: 3 → 6 (+3) — pricing tiers, resource tracking, usage overview

**Remaining gaps vs Heroku:**
1. **Git push deploy** — still a stub (biggest DX gap)
2. **CLI tool** — no Wokku CLI yet
3. **2FA** — not implemented
4. **CI/CD pipelines** — no pipeline/staging concept
5. **Stripe checkout** — billing model exists but checkout flow untested
6. **Historical metrics charts** — only live data, no 24h charts
7. **GitLab/Bitbucket** — only GitHub supported

**Remaining gaps vs Coolify:**
1. **Docker Compose deploy** — only via templates, not arbitrary
2. **Nixpacks builder** — Dokku uses buildpacks, not Nixpacks
3. **Wildcard domains/SSL** — not exposed in UI
4. **Pushover notifications** — not implemented

**Unique advantages over both:**
- **Meilisearch, ClickHouse, NATS** as managed add-ons (neither has these)
- **HTTP Auth** for staging protection (neither has this in UI)
- **Per-dyno pricing with tier restrictions** (Coolify doesn't have this)
- **App console sandboxing** (Coolify gives full server access)
- **Heroku-compatible UX** (familiar to Heroku users migrating)

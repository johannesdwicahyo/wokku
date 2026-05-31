<!-- Curated public changelog. Founder edits this. Do NOT auto-sync from the private repo. -->

## 2026-05 — Public beta

Wokku Cloud opened public beta in May with `git push` deploys, Jakarta region, and IDR / QRIS / VA / e-wallet payments — Rupiah-native end to end. Big month after that; rolled up by theme below.

### Billing & pricing

- **Monthly invoice billing.** Plans now billed once a month with a 7-day free trial on Solo / Pro / Team. Replaces the earlier hourly + deposit model.
- **Plan bundles.** Every paid plan ships with sized Postgres, Redis, and MinIO object storage — no separate addon billing. Free tier gets shared Postgres + Redis + 1 GB object storage.
- **Team plan extra seats: $3 / Rp 45.000 per month.** Cheaper marginal seat than any major comparable PaaS.
- **New `/pricing` comparison.** 10 capability sections (Compute, Networking, Databases, Deploys, Observability, Notifications, Team, Security, Developer Experience, Support), 45+ features mapped Free → Solo → Pro → Team.

### Workspaces & teams

- **Personal + multiple org workspaces.** Every account has a personal workspace; create as many org workspaces as you need.
- **Workspace switcher** in the topbar moves you between contexts; everything (apps, billing, members, audit log) re-scopes.
- **Team plan v1** with invite-by-email and role-based access (Viewer / Member / Admin).
- **App Transfer.** Move an app to another user without redeploying — useful for agencies handing off projects.

### Observability

- **Persisted logs.** Every container log line is shipped from your host and stored with per-plan retention (1 day on Free → 30 days on Team). Live tail still works; you can scroll backwards.
- **Per-app HTTP request monitor.** p50 / p95 / p99 sampling plus 5-minute aggregate buckets; full picture of latency and error rate per app.
- **CPU / RAM / network metrics** with per-plan retention windows; high-resolution recent data, hourly rollups for capacity planning.
- **Database stats page.** Connections, disk usage, slow queries, top tables — straight from the Dokku host.
- **Audit log.** Every deploy, config change, member add, billing event — filterable by user / action / time, CSV export.
- **Log drains.** Forward logs to Datadog, Logtail, Papertrail, or any HTTPS / syslog endpoint.

### Deploys

- **PR Previews** (Pro / Team). Auto-deploy every pull request to a preview subdomain; preview is torn down when the PR closes.
- **Scheduled Tasks** (Pro / Team). Cron jobs from the dashboard, in your app container, with per-run logs.
- **11 framework starter templates.** Rails, Next.js, Django, Laravel, Phoenix, Express, Astro, TanStack Start, Flask, FastAPI, Go — one-click deploy from `/templates`.
- **Template gallery polish.** Brand logos via SimpleIcons CDN, version badges, search.

### Docs

- **Brutalist redesign.** New typography, sidebar, search, code-block tabs.
- **Bilingual docs.** Every page available in English and Bahasa Indonesia via the language switcher.
- **Deep-dive guides added** for Billing / Invoices, Plan Bundles, Observability / Retention, Workspaces, Audit Log, and more — the full sidebar reorganized around what people actually search for.
- **Open Source Edition page** documenting what's in the OSS web UI vs the Cloud surface.

### Open source

- **OSS edition narrowed to web UI only.** REST API, CLI, MCP server, and mobile app are Cloud-only. Lets us ship the OSS edition on a sustainable cadence.
- **Monthly release cadence.** OSS releases tag on the 1st of each month as `vYYYY.MM` — bug fixes from the previous month's Cloud deploys plus web-UI feature additions.

### Naming

- **`slot` → `box`** everywhere — schema, dashboard copy, CLI, API, docs. "Box" is the unit you scale; "Small / Medium / Large / X-Large" are the sizes.

### Coming next

- **`*.wokku.app` as the canonical app subdomain.** Cutover code is in place. Existing `*.wokku.cloud` subdomains keep resolving forever — no broken external links.

---

## 2026-04 — Pre-launch

- **Wokku Cloud** soft launch on `wokku.cloud`. Single Jakarta region, free tier, paid plans in private beta.
- **One-click templates** (50+) covering Ghost, n8n, WordPress, Uptime Kuma, Strapi, Plausible, and more.
- **Managed Postgres + Redis** addons, automatic SSL via Let's Encrypt, custom domains.
- **Free tier:** shared Postgres (150 MB), free dyno for hobby projects.
- **Notifications:** Slack + Discord deploy alerts.
- **Per-app CDN toggle** (Cloudflare proxy on / off).
- **Framework starters:** Rails, Next.js, Django, Laravel, Phoenix, Express, Astro, Flask, FastAPI, Go.

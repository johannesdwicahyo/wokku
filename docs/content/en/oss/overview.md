---
title: Open Source Edition
summary: "The OSS edition of Wokku is the web UI only — REST API, CLI, MCP server, and mobile app are Cloud-only. Releases ship on a monthly cadence."
eyebrow: open source
last_updated: 2026-05-29
---

# Open Source Edition

Wokku Cloud (this site, `wokku.cloud`) is the managed PaaS we operate for you. The **Community Edition** at [github.com/johannesdwicahyo/wokku](https://github.com/johannesdwicahyo/wokku) is the open-source Rails app you can run on your own infrastructure — same dashboard, smaller surface.

## What's in the OSS edition

| Surface | OSS | Cloud |
|---|---|---|
| **Web UI / dashboard** | ✅ | ✅ |
| Apps, databases, domains, SSL, logs, metrics | ✅ | ✅ |
| Teams + role-based permissions | ✅ | ✅ |
| Templates gallery (one-click deploys) | ✅ | ✅ |
| **REST API** (`/api/v1/*`) | — | ✅ |
| **CLI** (`wokku` binary) | — | ✅ |
| **MCP server** (Claude Code integration) | — | ✅ |
| **Mobile app** (iOS / Android) | — | ✅ |
| Monthly invoice billing + plan bundles | — | ✅ |
| Shared Postgres + Redis addons | — | ✅ |
| Vector-based log persistence | — | ✅ |
| Audit log / activity stream | basic | full |
| Cloudflare DNS automation | — | ✅ |
| iPaymu / Stripe payments | — | ✅ |

The web UI is the same Rails app and ViewComponent design system. Everything you see in `wokku.cloud` screenshots renders identically in your self-hosted instance.

## Why the surface shrank

We unbundled CLI, API, MCP, and mobile from the OSS edition because:

— **Maintenance burden** — each surface had its own auth flow, rate limits, and release cadence. Shipping all of them to self-hosters meant every OSS release was a multi-platform release.
— **Cloud-specific dependencies** — the REST API in production assumes Cloud-side infrastructure (request signing, fleet-wide rate limits, log drains). Pulling that out cleanly was always going to be a porting tax.
— **Mobile + MCP are auth-gated services** — they call back into our managed auth layer. Forking them to support per-instance OAuth setups was never going to be worth the support load.

If you self-host and want any of these, the path forward is to upgrade to Cloud — same UI, same data model, plus the surfaces we operate centrally.

## Release cadence

OSS releases ship **monthly, on the 1st of each month**. Each release is tagged `vYYYY.MM` (e.g. `v2026.06`) and includes:

— All bug fixes from the previous month's Cloud deploys
— Web-UI feature additions that don't depend on Cloud-only infrastructure
— Migrations and schema changes (always reversible)
— A CHANGELOG entry summarizing what's in

You can pin to a specific version, or follow `main` for the bleeding edge — we keep `main` green via CI but only the tagged releases are tested end-to-end on a clean install.

## Upgrading

```bash
cd wokku
git fetch origin
git checkout v2026.06   # or whatever the latest tag is
bundle install
bin/rails db:migrate
bin/kamal redeploy      # or your equivalent deploy command
```

Upgrades are designed to be **forward-only and rollback-safe** within a release. We don't ship migrations that can't be reversed cleanly inside a single release window.

## License

OSS is **AGPL-3.0**. You can run it for yourself, your team, or your company. If you fork and modify it as a hosted service, you owe your users the source of your changes.

If you want to bundle the OSS edition into a closed-source product or offer it as a managed service, contact [hello@wokku.cloud](mailto:hello@wokku.cloud) for a commercial license.

## Getting started with OSS

```bash
git clone https://github.com/johannesdwicahyo/wokku
cd wokku
bin/setup
bin/dev
```

The README has the full setup including PostgreSQL, Redis, host runtime setup (Docker Swarm, Caddy, wokkud), and Cloudflare DNS (if you want it). For production, see [docs/infra/](https://github.com/johannesdwicahyo/wokku/tree/main/docs/infra) in the repo.

## What if I need the API or CLI today?

The simplest path is to use [Wokku Cloud](https://wokku.cloud) — the free plan covers a single hobby app and includes the full REST API, CLI, and MCP surface.

If you specifically need the API on self-hosted infrastructure, contact us about an enterprise license — we can ship the API service as a separate container alongside an OSS web-UI install.

## See also

— [GitHub repo](https://github.com/johannesdwicahyo/wokku) — source, issues, releases
— [Beta notice](/docs/beta) — current status of Wokku Cloud
— [FAQ](/docs/troubleshooting/faq) — CE vs Cloud differences

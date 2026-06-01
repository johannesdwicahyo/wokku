# Wokku

[![Deploy to Wokku](https://img.shields.io/badge/Deploy%20to-Wokku-22C55E?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0id2hpdGUiPjxwYXRoIGQ9Ik0xMyAxMFYzTDQgMTRoN3Y3bDktMTFoLTd6Ii8+PC9zdmc+)](https://wokku.cloud/deploy)

**Web UI for [Dokku](https://dokku.com).** Open-source cloud platform for developers and creators — deploy apps with `git push`, install popular open-source tools in one click, manage databases, domains, SSL, and more from a beautiful dashboard.

> Self-host on your own servers or use our managed cloud at [wokku.cloud](https://wokku.cloud). No vendor lock-in.

## Features

| Feature | Description |
|---|---|
| **1-Click App Templates** | 50+ curated templates — deploy n8n, Ghost, Uptime Kuma, Grafana, and more instantly |
| **Git Push Deploys** | Push to deploy with automatic builds, zero-downtime deployments, rollbacks |
| **GitHub Integration** | Connect repos, auto-deploy on push, browse branches from dashboard |
| **Web Terminal** | Browser-based SSH terminal (xterm.js) for your Dokku servers |
| **Real-time Deploy Logs** | Stream build output live during deployments |
| **9 Database Engines** | PostgreSQL, MySQL, MariaDB, Redis, MongoDB, Memcached, RabbitMQ, Elasticsearch, MinIO |
| **Database Backups** | Scheduled + on-demand backups to S3, Cloudflare R2, MinIO, Backblaze B2, DO Spaces |
| **Custom Domains + SSL** | Automatic Let's Encrypt certificates, auto-renewal |
| **Multi-Server** | Connect multiple Dokku servers across regions, health checks, auto-sync |
| **Live Metrics** | Real-time CPU/memory stats, 24-hour history charts |
| **Notifications** | Email, Slack, Discord, Telegram, Webhook — deploy alerts and more |
| **Activity Log** | Track all actions — deploys, config changes, team activity |
| **OAuth Sign-in** | GitHub and Google login |
| **Teams & RBAC** | Invite members with viewer/member/admin roles |
| **Shared Add-on Engines** *(v0.2.0)* | One host container per engine (Postgres / Redis / Memcached / RabbitMQ / Meilisearch), per-tenant DB/role on attach. Saves ~250 MB RAM per addon vs one container each. |

## What's New in v0.2.0 (May 2026)

- **Shared add-on engines.** A new family of upstream Dokku plugins
  ([dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres),
  [-redis](https://github.com/johannesdwicahyo/dokku-shared-redis),
  [-minio](https://github.com/johannesdwicahyo/dokku-shared-minio),
  [-memcached](https://github.com/johannesdwicahyo/dokku-shared-memcached),
  [-rabbitmq](https://github.com/johannesdwicahyo/dokku-shared-rabbitmq),
  [-meilisearch](https://github.com/johannesdwicahyo/dokku-shared-meilisearch))
  let one host container serve hundreds of small apps. Wokku auto-provisions
  a per-tenant DB+user on app create and tears it down on destroy.
- **UI polish.** Sidebar admin group collapsed to one entry, app overview log
  glance is now Turbo-frame wrapped (no more "Content missing" flash), release
  history dropped the misleading "config change" badge on plain git-push
  releases, new-app form is denser, Material Symbols Outlined now loads
  globally.
- **Internal scaffolding for Bundle v2** ships behind `BUNDLE_V2_ENABLED=false`
  — see the [Roadmap](#roadmap) section below.

Full changelog: see the [v0.2.0 GitHub Release](https://github.com/johannesdwicahyo/wokku/releases/tag/v0.2.0).

## Quick Start

### Docker Compose (recommended)

```bash
git clone https://github.com/johannesdwicahyo/wokku.git
cd wokku
cp .env.example .env
# Edit .env — set SECRET_KEY_BASE (run: openssl rand -hex 64)

docker compose up -d
docker compose exec web bin/rails db:setup
```

Open `http://localhost:3000` — default login: `admin@wokku.cloud` / `password123456`

### Manual Setup

**Requirements:** Ruby 3.4+, PostgreSQL 16+, Redis 7+

```bash
git clone https://github.com/johannesdwicahyo/wokku.git
cd wokku
bundle install
bin/rails db:setup
bin/dev
```

## Connecting a Dokku Server

> On the managed cloud at [wokku.cloud](https://wokku.cloud), servers are
> platform infrastructure managed by the Wokku team — every user can
> deploy onto them without setup. The steps below apply to self-hosted
> installs, where the first admin connects their own Dokku server.

1. Go to **Servers > Add Server** in the dashboard
2. Enter your Dokku server's hostname, SSH port, and private key
3. Wokku connects over SSH and syncs all existing apps and databases

## Deploying with `git push`

Register your SSH public key in **Profile → SSH Keys**, then push to the
Wokku git gateway:

```bash
git remote add wokku git@wokku.cloud:my-app
git push wokku main
```

The gateway authenticates you by SSH key, authorizes against your team's
access to `my-app`, and proxies the push to the underlying Dokku host —
you never need to know which server your app runs on. Direct pushes to
`dokku@<server>:my-app` still work as a fallback.

## 1-Click App Templates

Deploy popular open-source tools with a single click. Browse from the dashboard or the [template gallery](https://wokku.cloud/dashboard/templates).

**Popular templates:** n8n, Waha, Ghost, Uptime Kuma, Umami, Vaultwarden, NocoDB, Grafana, Cal.com, Listmonk, Miniflux, Supabase, and 40+ more.

Templates use standard Docker Compose YAML format. Community contributions welcome — just add a `docker-compose.yml` to `app/templates/<name>/` and open a PR.

## Architecture

```
wokku (Rails 8.1)
├── Dashboard UI        Tailwind + Hotwire (Turbo + Stimulus)
├── Web Terminal        xterm.js + ActionCable + SSH
├── Background Jobs     Solid Queue (deploys, backups, health checks, metrics)
├── Dokku Integration   SSH-based command execution via net-ssh
├── GitHub Integration  GitHub App for auto-deploy on push
└── SSH Git Gateway     git@wokku.cloud routes pushes to the right Dokku host
```

**Stack:** Rails 8.1 / PostgreSQL / Redis / Solid Queue / Solid Cache / Tailwind CSS / Hotwire

## CLI

The `wokku` CLI is a separate gem — see [johannesdwicahyo/wokku-cli](https://github.com/johannesdwicahyo/wokku-cli).

```bash
brew install johannesdwicahyo/tap/wokku
# or: gem install wokku-cli

wokku auth:login
wokku apps:create my-app
wokku logs my-app -f
```

The CLI talks to the REST API, which is a managed-cloud feature and is **not** bundled in this OSS web-UI repo. The CLI only works against Wokku Cloud. Self-host users should use the web UI directly, or `ssh dokku@your-host` for shell ops.

## Claude Code Plugin

The official [wokku-plugin](https://github.com/johannesdwicahyo/wokku-plugin) for Claude Code wraps the REST API in 57 MCP tools and 4 guided workflows. Like the CLI, it's Wokku-Cloud-only — the API isn't shipped in this OSS repo. Install:

```bash
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

Then ask Claude: *"Deploy this project to Wokku as my-app"* or *"Troubleshoot why my-app is crashing"*.

## Database Backups

Configure S3-compatible backup destinations per server. Supports:
- **AWS S3** — default
- **Cloudflare R2** — no egress fees
- **MinIO** — self-hosted
- **Backblaze B2** — cheapest storage
- **DigitalOcean Spaces**
- **Wasabi** — no egress fees

Automatic daily backups with configurable retention. On-demand backup and one-click restore from the dashboard.

## Deployment

Deploy with [Kamal](https://kamal-deploy.org):

```bash
kamal setup
```

Or with Docker on any VPS:

```bash
docker compose -f docker-compose.yml up -d
```

## Roadmap

The `BUNDLE_V2_ENABLED` flag in this release ships dormant. When flipped on a
self-hosted install, it switches the app sizing model from per-process dyno
tiers to a "box" abstraction (sleeping / small / medium / large / xlarge) and
unlocks the shared-engine add-ons as a one-click attach + a dedicated upgrade
flow (`pg_dump` → cutover → 24h grace → drop). The managed cloud runs this
mode in production; self-hosters who want to try it should read the migration
notes on [wokku.cloud/docs/bundle-v2](https://wokku.cloud/docs/bundle-v2)
before flipping.

## Contributing

### Adding Templates

1. Create `app/templates/<name>/docker-compose.yml` with metadata comments:
```yaml
# documentation: https://example.com
# slogan: Short description of the app
# category: automation
# tags: workflow, node
# icon: automation
# port: 5678

services:
  myapp:
    image: myapp:latest
```

2. Open a PR to this repo

### Development

```bash
bundle exec rspec
```

(Legacy Minitest tests still pass under `bin/rails test`; new tests should be RSpec.)

## Wokku Cloud

[wokku.cloud](https://wokku.cloud) is the commercial managed service. It adds, on top of this open-source web UI:

- **REST API + CLI + Claude Code plugin** — managed-cloud-only surface, billed and rate-limited per account
- **Per-box billing** with IDR + USD support (Bundle v2 plans: Solo / Pro / Team)
- **Eco / sleeping boxes** with auto-wake on request
- **Auto-placement** across our managed Dokku fleet
- **Per-app Cloudflare CDN** toggle
- **PR previews** for GitHub-connected apps
- **Mobile companion app** (in development)

The OSS web UI in this repo is fully functional for a single Dokku server + Devise sign-in. The managed service exists for teams who want multi-server, billing, observability, and the API surface on tap.

## License

[GNU Affero General Public License v3.0](LICENSE)

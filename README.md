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
| **REST API** | 16 resource endpoints with token authentication |
| **CLI** | `wokku` command — 50+ commands mirroring the Heroku experience |

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

1. Go to **Servers > Add Server** in the dashboard
2. Enter your Dokku server's hostname, SSH port, and private key
3. Wokku connects over SSH and syncs all existing apps and databases

Or via CLI:

```bash
wokku servers:add my-server --host dokku.example.com --ssh-key ~/.ssh/id_ed25519
```

## 1-Click App Templates

Deploy popular open-source tools with a single click. Browse from the dashboard or the [template gallery](https://wokku.cloud/dashboard/templates).

**Popular templates:** n8n, Waha, Ghost, Uptime Kuma, Umami, Vaultwarden, NocoDB, Grafana, Cal.com, Listmonk, Miniflux, Supabase, and 40+ more.

Templates use standard Docker Compose YAML format. Community contributions welcome — just add a `docker-compose.yml` to `app/templates/<name>/` and open a PR.

## Architecture

```
wokku (Rails 8.1)
├── Dashboard UI        Tailwind + Hotwire (Turbo + Stimulus)
├── REST API v1         Token-authenticated JSON API
├── CLI                 Thor-based gem, mirrors Heroku CLI
├── Web Terminal        xterm.js + ActionCable + SSH
├── Background Jobs     Solid Queue (deploys, backups, health checks, metrics)
├── Dokku Integration   SSH-based command execution via net-ssh
├── GitHub Integration  GitHub App for auto-deploy on push
└── Git Receiver        Accept git push deploys on port 2222
```

**Stack:** Rails 8.1 / PostgreSQL / Redis / Solid Queue / Solid Cache / Tailwind CSS / Hotwire

## CLI

```bash
gem install wokku

wokku login
wokku apps:create my-app --server my-server
wokku config:set my-app DATABASE_URL=postgres://...
wokku domains:add my-app app.example.com
wokku ps:scale my-app web=2 worker=1
wokku logs my-app --tail
```

## API

All endpoints are under `/api/v1/` with Bearer token authentication.

```bash
curl -X POST localhost:3000/api/v1/auth/login \
  -d '{"email":"admin@wokku.cloud","password":"password123456"}'

curl -H "Authorization: Bearer <token>" localhost:3000/api/v1/apps
```

**Resources:** apps, servers, databases, domains, releases, config, logs, ps, ssh_keys, teams, members, notifications

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
bin/rails test
```

## Claude Code Plugin

Install the official Wokku plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — 57 tools + 4 guided workflows for deploying, managing, and troubleshooting your apps through natural language.

```bash
claude plugin marketplace add johannesdwicahyo/wokku-plugin
claude plugin install wokku@wokku
```

Then ask Claude: *"Deploy this project to Wokku as my-app"* or *"Troubleshoot why my-app is crashing"*.

See [mcp/README.md](mcp/README.md) for the underlying MCP server (55 tools, 100% API coverage) and full setup instructions.

## Enterprise Edition

Wokku follows an open-core model. The community edition (this repo) is fully functional under AGPL-3.0. The Enterprise Edition adds:

- Usage-based hourly billing (Stripe)
- Dyno tiers with resource management
- Eco dynos (auto-sleep idle apps)
- Auto-placement (bin-packing server selection)
- Mobile companion app

See [wokku.cloud](https://wokku.cloud) for the managed cloud and enterprise features.

## License

[GNU Affero General Public License v3.0](LICENSE)

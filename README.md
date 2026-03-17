# Wokku

**Web UI for [Dokku](https://dokku.com).** Open-source Heroku alternative — deploy apps with `git push`, manage databases, domains, SSL, scaling, and metrics from a beautiful dashboard, REST API, or CLI.

> Self-host your own PaaS on any VPS. No vendor lock-in.

## Features

| | Feature | Description |
|---|---|---|
| **Apps** | Deploy & manage | `git push` deploys, restart/stop/start, release history, rollback |
| **Databases** | 6 engines | PostgreSQL, MySQL, Redis, MongoDB, Memcached, RabbitMQ |
| **Domains** | Custom domains | Add domains, automatic Let's Encrypt SSL, auto-renewal |
| **Config** | Env variables | Set, edit, delete environment variables per app |
| **Scaling** | Process scaling | Scale web, worker, and custom process types independently |
| **Metrics** | Live monitoring | Real-time CPU/memory stats, 24-hour history charts |
| **Logs** | Log streaming | Live log tailing with color-coded output |
| **Servers** | Multi-server | Connect multiple Dokku servers, health checks, auto-sync |
| **Teams** | Collaboration | Invite members with viewer/member/admin roles |
| **Notifications** | Email alerts | Deploy notifications via email |
| **API** | Full REST API | 16 resource endpoints with token authentication |
| **CLI** | `wokku` command | 50+ commands mirroring the Heroku CLI experience |
| **DNS** | Auto-verification | Background DNS verification before SSL provisioning |

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

Open `http://localhost:3000` — default login: `admin@wokku.local` / `password123456`

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

## Architecture

```
wokku (Rails 8.1)
├── Dashboard UI        Tailwind + Hotwire (Turbo + Stimulus)
├── REST API v1         Token-authenticated JSON API
├── CLI                 Thor-based gem, mirrors Heroku CLI
├── Background Jobs     Solid Queue (health checks, metrics, DNS, SSL, deploys)
├── Dokku Integration   SSH-based command execution via net-ssh
└── Git Receiver        Accept git push deploys on port 2222
```

**Stack:** Rails 8.1 / PostgreSQL / Redis / Solid Queue / Solid Cache / Tailwind CSS / Hotwire

## CLI

Install the CLI gem:

```bash
gem install wokku
```

```bash
wokku login
wokku apps:create my-app --server my-server
wokku config:set my-app DATABASE_URL=postgres://...
wokku domains:add my-app app.example.com
wokku domains:ssl my-app app.example.com
wokku ps:scale my-app web=2 worker=1
wokku logs my-app --tail
wokku releases my-app
wokku releases:rollback my-app v3
```

## API

All endpoints are under `/api/v1/` with Bearer token authentication.

```bash
# Get an API token
curl -X POST localhost:3000/api/v1/auth/login \
  -d '{"email":"admin@wokku.local","password":"password123456"}'

# List apps
curl -H "Authorization: Bearer <token>" localhost:3000/api/v1/apps

# Create an app
curl -X POST -H "Authorization: Bearer <token>" localhost:3000/api/v1/apps \
  -d '{"name":"my-app","server_id":1}'
```

**Resources:** apps, servers, databases, domains, releases, config, logs, ps, ssh_keys, teams, members, notifications

## Deployment

Wokku ships with [Kamal](https://kamal-deploy.org) configuration for production deployment:

```bash
# Edit config/deploy.yml with your server details
kamal setup
```

Or deploy with Docker on any VPS:

```bash
docker compose -f docker-compose.yml up -d
```

## Testing

```bash
bin/rails test
```

## Enterprise Edition

Wokku follows an open-core model. The community edition (this repo) is a fully functional PaaS under AGPL-3.0. The Enterprise Edition adds:

- Billing & Stripe integration
- Usage-based plan limits
- Dyno tiers with resource management
- Eco dynos (auto-sleep idle apps)
- Auto-placement (bin-packing server selection)
- Slack & webhook notifications

See [wokku.dev](https://wokku.dev) for details.

## License

[GNU Affero General Public License v3.0](LICENSE)

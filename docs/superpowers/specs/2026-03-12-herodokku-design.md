# Wokku Design Spec

**Date:** 2026-03-12
**Status:** Approved

## Overview

Wokku is a full Heroku-like PaaS built on top of Dokku. It provides a polished web dashboard (Rails 8 + Hotwire), a local CLI (Ruby gem), and an MCP server for AI-assisted infrastructure management via Claude Code.

It communicates with one or more Dokku servers over SSH, giving users a unified interface to manage apps, databases, domains, scaling, logs, and more — without touching Dokku directly.

## Goals

- Commercial PaaS product from day one — compete with Heroku, Railway, Render
- Heroku-like developer experience built on Dokku
- Multi-server fleet management (each app on one Dokku server, customers distributed across servers)
- Dyno-based pricing with tiered resource limits
- Self-hostable open-source core may be added later as an additional offering
- Pure Ruby stack (Rails + Ruby gem CLI)

## Architecture

```
                         ┌──────────────────┐
┌─────────────┐          │                  │     ┌─────────────────┐
│  wokku  │───API───▶│                  │─SSH─▶ Dokku Server   │
│  CLI (gem)  │          │                  │     │  (one or many)  │
└─────────────┘          │   Rails 8 App    │     └─────────────────┘
                         │                  │
┌──────────────┐         │  - Hotwire/Turbo │
│  Claude Code │───API──▶│  - Action Cable  │
│  (via MCP)   │         │  - Solid Queue   │
└──────────────┘         │                  │
                         │  PostgreSQL      │
┌──────────────┐         │  Redis (cable)   │
│   Browser    │──HTTP──▶│                  │
└──────────────┘         └──────────────────┘
                                │
                         ┌──────────────────┐
                         │  Git SSH Server  │
┌──────────────┐         │  (port 2222)     │
│  git push    │───SSH──▶│  Receives push,  │
└──────────────┘         │  forwards to     │
                         │  Dokku           │
                         └──────────────────┘
```

### Key Technology Choices

- **Rails 8** with Hotwire/Turbo/Stimulus for the dashboard (no separate frontend)
- **Action Cable** for real-time log streaming and deploy progress
- **Redis** as Action Cable adapter (required for multi-process WebSocket support)
- **Solid Queue** for background jobs (deploys, SSH commands, health checks) — uses the database, not Redis
- **Thor-based Ruby gem** for the CLI (`gem install wokku`)
- **MCP server** in the same gem for Claude Code integration
- **net-ssh** gem to communicate with Dokku servers over the network
- **PostgreSQL** for all persistent data
- **Devise + Pundit** for auth and authorization

### Three Clients, One API

1. **Web dashboard** — Hotwire/Turbo, session auth via Devise
2. **CLI gem** — Thor, token auth via `Authorization: Bearer <token>`
3. **MCP server** — JSON-RPC over stdio, reads auth from `~/.wokku/config`

All three clients hit the same Rails REST API (`/api/v1/*`).

## Data Model

### Entities

| Model | Purpose | Key Fields |
|-------|---------|------------|
| **User** | Auth, profile | email, password, role |
| **Team** | Group users | name, owner_id |
| **TeamMembership** | User-Team join with role | user_id, team_id, role (admin/member/viewer) |
| **Server** | A Dokku host | name, host, port, ssh_key (encrypted), team_id, status, region, capacity_total_mb, capacity_used_mb |
| **AppRecord** | A Dokku app ("App" conflicts with Rails) | name, server_id, team_id, status, created_by |
| **Release** | Versioned release (maps to "releases" in CLI) | app_record_id, version (auto-increment), deploy_id (nullable), description, created_at |
| **Deploy** | Deploy execution record | app_record_id, release_id, status (pending/building/succeeded/failed), commit_sha, log, started_at, finished_at |
| **Domain** | Custom domain | app_record_id, hostname, ssl_enabled, verification_status (pending/verified/failed), verification_token, verified_at |
| **EnvVar** | Config/env variable | app_record_id, key, encrypted_value |
| **DatabaseService** | Dokku service (postgres, redis, etc.) | server_id, service_type, name, status |
| **AppDatabase** | Link between app and database | app_record_id, database_service_id, alias (env var name, e.g. DATABASE_URL) |
| **Certificate** | SSL cert | domain_id, expires_at, auto_renew |
| **ProcessScale** | Dyno scaling | app_record_id, process_type (web/worker), count |
| **Notification** | Alert config | app_record_id (nullable), team_id, channel (email/slack/webhook), events, config (JSON) |
| **ApiToken** | Auth token for CLI/MCP | user_id, token_digest (hashed), name, last_used_at, expires_at, revoked_at |
| **SshPublicKey** | User's SSH key for git push auth | user_id, name, public_key, fingerprint |
| **Plan** | Subscription plan definition | name (free/hobby/pro/business), monthly_price_cents, included_dyno_tier, included_dyno_count, max_apps, max_databases, max_db_size_mb, custom_domains, team_members |
| **Subscription** | User's active plan | user_id, plan_id, stripe_subscription_id, stripe_customer_id, status (active/past_due/canceled), current_period_end |
| **DynoTier** | Resource tier definition | name (eco/basic/standard-1x/standard-2x/performance), memory_mb, cpu_shares, price_cents_per_month, sleeps |
| **DynoAllocation** | App's dyno configuration | app_record_id, dyno_tier_id, process_type, count |
| **Invoice** | Monthly billing record | subscription_id, stripe_invoice_id, amount_cents, status (draft/open/paid/void), period_start, period_end |
| **UsageEvent** | Tracks billable events | subscription_id, event_type (dyno_hour/db_provision/addon), quantity, recorded_at, metadata (JSON) |

### Security

- EnvVar values are encrypted at rest (Rails encrypted attributes)
- Server SSH keys are encrypted at rest
- API tokens are hashed (not stored in plain text)

### Relationships

```
User ──▶ Subscription ──▶ Plan
  │           │
  │           └──▶ Invoice, UsageEvent
  │
  ├──▶ TeamMembership ──▶ Team ──▶ Server ──▶ AppRecord
  │                                     │            │
  ├──▶ ApiToken                         ▼            ├──▶ DynoAllocation ──▶ DynoTier
  └──▶ SshPublicKey             DatabaseService      ├──▶ Release ──▶ Deploy
                                        │            ├──▶ Domain ──▶ Certificate
                                        ▼            ├──▶ EnvVar
                                   AppDatabase       └──▶ Notification (optional)
                                  (links apps ↔ dbs)
                                                     Team ──▶ Notification (team-wide)
```

## Feature Specifications

### 1. App Management

| Action | Dokku Command |
|--------|--------------|
| Create | `apps:create <name>` |
| Delete | `apps:destroy <name>` |
| Restart | `ps:restart <name>` |
| Stop/Start | `ps:stop <name>` / `ps:start <name>` |
| List | `apps:list` |
| Rename | `apps:rename <old> <new>` |
| Info | `apps:report <name>` |

### 2. Environment Variables

| Action | Dokku Command |
|--------|--------------|
| Set | `config:set <app> KEY=VAL` |
| Unset | `config:unset <app> KEY` |
| List | `config:show <app>` |

Values stored encrypted in Wokku's DB. See "Data Synchronization Strategy" below.

### 3. Domains & SSL

| Action | Dokku Command |
|--------|--------------|
| Add domain | `domains:add <app> <domain>` |
| Remove | `domains:remove <app> <domain>` |
| Enable SSL | `letsencrypt:enable <app>` |
| Auto-renew | `letsencrypt:cron-job --add` |

### 4. Databases/Addons

| Action | Dokku Command |
|--------|--------------|
| Create | `<service>:create <name>` |
| Link to app | `<service>:link <db> <app>` |
| Unlink | `<service>:unlink <db> <app>` |
| Info | `<service>:info <db>` |

Supported services: postgres, redis, mysql, mongodb, memcached, rabbitmq (any Dokku service plugin).

### 5. Log Streaming

| Action | Dokku Command |
|--------|--------------|
| Tail logs | `logs <app> --tail` (long-running SSH channel) |
| Recent logs | `logs <app> --num <n>` |

Streamed via Action Cable to the browser. CLI pipes to stdout. Deploy logs are stored in the Deploy record.

### 6. Git Deploy

```
Developer                 Wokku                    Dokku Server
   │                         │                              │
   │  git push wokku main│                              │
   │────────────────────────▶│                              │
   │                         │  Authenticates via SSH key   │
   │                         │  Creates Deploy record       │
   │                         │  git push dokku main         │
   │                         │─────────────────────────────▶│
   │                         │  Streams build output        │
   │  Deploy log stream      │◀─────────────────────────────│
   │◀────────────────────────│                              │
   │                         │  Updates Deploy status       │
   │  Done                   │                              │
   │◀────────────────────────│                              │
```

#### Git SSH Server Details

Wokku runs a lightweight Git SSH server on port 2222 using the `sshd` approach (a small Ruby process using `net-ssh` that accepts incoming SSH connections).

**Authentication:** Users register SSH public keys in their Wokku account (stored in `SshPublicKey` model). The Git SSH server matches the incoming key fingerprint to a Wokku user. No system-level `authorized_keys` needed.

**Git URL format:** `ssh://wokku@<wokku-host>:2222/<app-name>.git`

The `wokku git:remote -a my-app` CLI command adds this remote automatically.

**Push flow:**
1. Developer pushes to Wokku git server
2. Server authenticates via SSH public key → resolves to User
3. Server checks Pundit authorization (is this user allowed to deploy this app?)
4. Creates a Release (incrementing version) and Deploy record (status: pending)
5. Receives the git pack data into a temporary bare repo on Wokku
6. Pushes from the temporary repo to the Dokku server via SSH (`git push dokku main`)
7. Streams Dokku's build output back to the developer AND stores it in Deploy.log
8. Updates Deploy status (succeeded/failed) and broadcasts via Action Cable
9. Fires notification jobs on completion

**Branch handling:** Only pushes to `main` (or the app's configured deploy branch) trigger deploys. Other branches are rejected with a message.

**Rollback:** Wokku stores the commit SHA for each Release. Rolling back to a previous version re-deploys that commit by doing `dokku git:from-archive` or pushing the tagged commit to Dokku. The rollback creates a new Release record pointing to the old commit.

**Temporary repos** are cleaned up after the deploy completes (success or failure).

### 7. Scaling

| Action | Dokku Command |
|--------|--------------|
| Scale | `ps:scale <app> web=2 worker=3` |
| Report | `ps:report <app>` |

### 8. Metrics/Monitoring

Dokku doesn't provide native metrics. Wokku polls:
- `docker stats --no-stream --format '{{json .}}'` via SSH for CPU/memory (JSON output for stability across Docker versions)
- `ps:report <app>` for process status

Metrics stored in DB, displayed with Chartkick in the dashboard. Background job polls every 60 seconds per server (not per app, to limit SSH overhead).

**Known limitation:** Polling via SSH has overhead. For production use with many apps, consider installing a lightweight metrics agent (e.g., cAdvisor, Dokku's resource plugin) on Dokku servers. This is a v2 improvement.

### 9. Team/User Management

Handled entirely in Wokku (not Dokku).

| Role | Permissions |
|------|------------|
| Admin | Full access to team's servers and apps |
| Member | Deploy, configure, view logs |
| Viewer | Read-only dashboard access |

Auth via Devise, authorization via Pundit policies.

### 10. Notifications

Deploy status changes trigger notifications via background jobs.

| Channel | Mechanism |
|---------|-----------|
| Email | Action Mailer |
| Slack | Incoming webhook |
| Webhook | Generic HTTP POST |

Notifications can be scoped to a **team** (all events for all apps) or to a **specific app**. App-level notifications override team-level for the same channel. Configurable per-event (deploy success, deploy failure, app crash).

### 11. Dyno Tiers & Resource Management

Each app's processes run on a specific dyno tier that controls resource limits via Dokku's resource plugin.

#### Tier Definitions

| Dyno Tier | RAM | CPU Share | Sleeps? | Price/dyno/mo |
|-----------|-----|-----------|---------|---------------|
| **Eco** | 256 MB | 1/4 vCPU | Yes (30min idle) | Free (included) |
| **Basic** | 512 MB | 1/2 vCPU | No | $5 |
| **Standard-1X** | 1 GB | 1 vCPU | No | $12 |
| **Standard-2X** | 2 GB | 2 vCPU | No | $25 |
| **Performance** | 4 GB | 4 vCPU | No | $50 |

#### Dokku Commands (per dyno change)

```bash
dokku resource:limit --memory <MB> --cpu <shares> <app>
dokku resource:reserve --memory <MB> <app>
```

When a user changes their dyno tier, Wokku runs the resource commands and triggers a restart.

#### Eco Dyno Sleep Mechanic

For free-tier Eco dynos, a background job implements the sleep/wake cycle:

1. **IdleCheckJob** runs every 5 minutes
2. Checks container CPU activity via `docker stats --no-stream`
3. If no meaningful activity for 30 minutes → `dokku ps:stop <app>`
4. App status set to `sleeping`
5. When a request arrives, an nginx-level health check detects the app is down
6. A **WakeAppJob** runs `dokku ps:start <app>` and returns a "Starting up..." page
7. Subsequent requests are served normally once the app is running

### 12. Billing & Subscriptions

#### Plans

| Plan | Monthly Fee | Included | Extra Dynos | Databases | Custom Domains | Teams |
|------|-------------|----------|-------------|-----------|---------------|-------|
| **Free** | $0 | 1 Eco dyno | — | 1 shared Postgres (10 MB) | `*.wokku.dev` only | No |
| **Hobby** | $7 | 1 Basic dyno | Buy at tier price | 1 Postgres (1 GB) | Yes + SSL | No |
| **Pro** | $25 | 1 Standard-1X | Buy at tier price | 3 databases (10 GB each) | Yes + SSL | Up to 3 members |
| **Business** | $49 | 2 Standard-1X | Buy at tier price | 5 databases (50 GB each) | Yes + SSL | Unlimited |

Users pay **plan fee + extra dyno costs**. Example: Pro user with `web=3` Standard-1X pays $25 + (2 extra × $12) = $49/mo.

#### Stripe Integration

- **Stripe Checkout** for initial subscription signup
- **Stripe Billing** for recurring payments with metered usage
- **Stripe Webhooks** to handle payment events (invoice.paid, invoice.payment_failed, customer.subscription.updated, etc.)
- **Usage records** pushed to Stripe for metered items (extra dynos, database overage)
- Plan changes (upgrade/downgrade) handled via Stripe's proration

#### Billing Flow

```
User signs up → Free plan (no card required)
         │
User upgrades → Stripe Checkout session → Card saved
         │
Monthly cycle:
  1. Stripe generates invoice
  2. Base plan fee + metered usage (extra dynos)
  3. Webhook: invoice.paid → Subscription stays active
  4. Webhook: invoice.payment_failed → Grace period (3 days) → Downgrade to Free
```

#### Enforcement

- **App limit:** Cannot create apps beyond plan limit. API returns 402.
- **Database limit:** Cannot create databases beyond plan limit.
- **Dyno tier:** Free plan locked to Eco. Hobby locked to Basic max. Pro/Business can use any tier.
- **Custom domains:** Free plan cannot add custom domains. API returns 402 with upgrade prompt.
- **Team members:** Free/Hobby cannot invite team members.
- Past-due subscriptions get 3-day grace period, then apps are stopped (not destroyed) and account is downgraded to Free limits.

### 13. Custom Domains

#### Default Subdomains

Every app automatically gets `<app-name>.wokku.dev`. Requires:
- Wildcard DNS: `*.wokku.dev` → load balancer IP
- Wildcard SSL via Let's Encrypt or Cloudflare

#### Custom Domain Flow

1. User adds domain via dashboard or CLI: `wokku domains:add -a my-app api.example.com`
2. Wokku checks plan allows custom domains (Hobby+ only)
3. Domain record created with `verification_status: pending`
4. User shown instructions: "Add a CNAME record pointing `api.example.com` to `domains.wokku.dev`"
5. **DnsVerificationJob** polls DNS every 2 minutes (up to 48 hours)
6. Once CNAME verified:
   - `verification_status: verified`
   - `dokku domains:add <app> api.example.com`
   - `dokku letsencrypt:enable <app>` for SSL
7. Domain is live

#### DNS Verification

```ruby
# Check if CNAME points to domains.wokku.dev
resolved = Resolv::DNS.new.getresources(hostname, Resolv::DNS::Resource::IN::CNAME)
verified = resolved.any? { |r| r.name.to_s == "domains.wokku.dev" }
```

Alternative: A-record pointing directly to the Dokku server IP (for apex domains).

### 14. Multi-Server Fleet Management

Wokku manages a pool of Dokku servers. Each app lives on one server. Customers are distributed across servers based on capacity.

#### Server Placement

When creating an app, Wokku picks the best server:

1. Filter servers by region (if user specified)
2. Filter by available capacity (total memory - used memory > app's dyno tier memory)
3. Pick the server with the most available capacity (bin-packing)

#### Regions

Servers are tagged with a `region` (e.g., `us-east`, `eu-west`). Users can choose a region when creating an app. Default region configurable per plan.

#### Capacity Tracking

- Each server tracks `capacity_total_mb` and `capacity_used_mb`
- Updated by SyncServerJob based on actual `docker stats` data
- Prevents over-provisioning: if no server has capacity, app creation is rejected with "No available capacity in region X"

## CLI Design

Built with Thor gem, distributed as a Ruby gem (`gem install wokku`).

Config stored in `~/.wokku/config` (API URL + auth token). Supports `-a <app>` flag or auto-detection from git remote in current directory.

### Command Reference

```bash
# Auth
wokku login
wokku logout
wokku whoami

# Apps
wokku apps
wokku apps:create <name>
wokku apps:destroy <name>
wokku apps:info -a <app>
wokku apps:rename <old> <new>

# Git & Deploys
wokku git:remote -a <app>
wokku releases -a <app>
wokku releases:info <version> -a <app>
wokku rollback <version> -a <app>

# Config
wokku config -a <app>
wokku config:set -a <app> KEY=VAL ...
wokku config:unset -a <app> KEY ...
wokku config:get -a <app> KEY

# Domains
wokku domains -a <app>
wokku domains:add -a <app> <domain>
wokku domains:remove -a <app> <domain>
wokku certs:auto -a <app>

# Addons
wokku addons -a <app>
wokku addons:create <type>
wokku addons:attach <addon> -a <app>
wokku addons:detach <addon> -a <app>
wokku addons:destroy <addon>
wokku addons:info <addon>

# Scaling
wokku ps -a <app>
wokku ps:scale -a <app> web=2 worker=3
wokku ps:restart -a <app>
wokku ps:stop -a <app>
wokku ps:start -a <app>

# Logs
wokku logs -a <app>
wokku logs -a <app> --tail

# Servers
wokku servers
wokku servers:add <name> --host <ip> --key <path>
wokku servers:remove <name>
wokku servers:info <name>

# Teams
wokku teams
wokku teams:create <name>
wokku teams:members <team>
wokku teams:invite <email> <team> --role <role>

# Notifications
wokku notifications -a <app>
wokku notifications:add <channel> --url <url>
```

## MCP Server

Ships inside the CLI gem. Launched via `wokku mcp:start`.

### Tools

```
apps_list(server:)
app_create(name:, server:)
app_info(app:)
app_destroy(app:, confirm:)
app_restart(app:)

config_list(app:)
config_set(app:, vars:)
config_unset(app:, keys:)

domains_list(app:)
domain_add(app:, hostname:)
domain_remove(app:, hostname:)
ssl_enable(app:)

databases_list(server:)
database_create(server:, type:, name:)
database_link(database:, app:)
database_unlink(database:, app:)
database_info(database:)

ps_list(app:)
ps_scale(app:, scaling:)
ps_restart(app:)

logs_recent(app:, lines: 100)

deploys_list(app:)
deploy_info(app:, version:)
rollback(app:, version:)

servers_list
server_add(name:, host:, port:, ssh_key:)
server_info(name:)
server_status(name:)

teams_list
team_members(team:)

notifications_list(app:)
```

### Claude Code Configuration

```json
{
  "mcpServers": {
    "wokku": {
      "command": "wokku",
      "args": ["mcp:start"]
    }
  }
}
```

## Project Structure

```
wokku/
├── Gemfile
├── Procfile                          # web + worker + git server
├── Dockerfile
├── docker-compose.yml
├── config/
│   ├── routes.rb
│   ├── cable.yml
│   └── queue.yml
├── app/
│   ├── models/
│   ├── controllers/
│   │   ├── api/v1/                   # JSON API (token auth)
│   │   └── dashboard/                # Hotwire HTML (session auth)
│   ├── views/dashboard/
│   ├── channels/
│   │   ├── log_channel.rb
│   │   └── deploy_channel.rb
│   ├── jobs/
│   │   ├── execute_ssh_job.rb
│   │   ├── deploy_job.rb
│   │   ├── health_check_job.rb
│   │   └── metrics_poll_job.rb
│   ├── services/dokku/
│   │   ├── client.rb                 # SSH connection manager
│   │   ├── apps.rb
│   │   ├── config.rb
│   │   ├── domains.rb
│   │   ├── databases.rb
│   │   ├── processes.rb
│   │   └── logs.rb
│   ├── services/git/
│   │   ├── server.rb
│   │   └── deploy_forwarder.rb
│   ├── policies/                     # Pundit
│   └── javascript/controllers/      # Stimulus
├── cli/
│   ├── wokku-cli.gemspec
│   ├── lib/wokku/
│   │   ├── cli.rb                    # Thor main
│   │   ├── commands/                 # Subcommands
│   │   ├── api_client.rb
│   │   └── config_store.rb
│   ├── mcp/
│   │   ├── server.rb
│   │   └── tools/
│   └── exe/wokku
└── docs/
```

## Deployment

### Docker Compose

```yaml
services:
  web:
    build: .
    ports: ["3000:3000"]
    depends_on: [db, redis]
  worker:
    build: .
    command: bin/jobs
  git:
    build: .
    command: bundle exec wokku git:server
    ports: ["2222:2222"]
  db:
    image: postgres:16
  redis:
    image: redis:7
```

### On Dokku

```bash
dokku apps:create wokku
dokku postgres:create wokku-db
dokku postgres:link wokku-db wokku
dokku config:set wokku SECRET_KEY_BASE=... DOKKU_SSH_KEY=...
dokku ports:add wokku tcp:2222:2222
git push dokku main
```

### Plain VPS

```bash
git clone <repo> && bundle install
rails db:setup
foreman start
```

## API Endpoints

All endpoints under `/api/v1/` use token auth (`Authorization: Bearer <token>`).
Dashboard controllers under `/dashboard/` use Devise session auth and return Turbo Frame HTML.

```
# Auth & Tokens
POST   /api/v1/auth/login              # Exchange email/password for API token
DELETE /api/v1/auth/logout             # Revoke current token
GET    /api/v1/auth/whoami             # Current user info
POST   /api/v1/auth/tokens             # Create named API token
DELETE /api/v1/auth/tokens/:id         # Revoke specific token
GET    /api/v1/auth/tokens             # List user's tokens

# SSH Keys
GET    /api/v1/ssh_keys                # List user's SSH keys
POST   /api/v1/ssh_keys               # Register SSH public key
DELETE /api/v1/ssh_keys/:id            # Remove SSH key

# Servers
GET    /api/v1/servers                 # List servers
POST   /api/v1/servers                 # Add server
GET    /api/v1/servers/:id             # Server info + status
DELETE /api/v1/servers/:id             # Remove server
GET    /api/v1/servers/:id/status      # Health check result

# Apps
GET    /api/v1/apps                    # List apps (filterable by server)
POST   /api/v1/apps                    # Create app
GET    /api/v1/apps/:id                # App info
PATCH  /api/v1/apps/:id                # Rename app
DELETE /api/v1/apps/:id                # Destroy app
POST   /api/v1/apps/:id/restart        # Restart
POST   /api/v1/apps/:id/stop           # Stop
POST   /api/v1/apps/:id/start          # Start

# Config (env vars)
GET    /api/v1/apps/:app_id/config     # List config vars
PATCH  /api/v1/apps/:app_id/config     # Set one or more vars (merge)
DELETE /api/v1/apps/:app_id/config     # Unset vars (keys in body)

# Domains
GET    /api/v1/apps/:app_id/domains
POST   /api/v1/apps/:app_id/domains
DELETE /api/v1/apps/:app_id/domains/:id
POST   /api/v1/apps/:app_id/domains/:id/ssl  # Enable Let's Encrypt

# Releases & Deploys
GET    /api/v1/apps/:app_id/releases          # Release history
GET    /api/v1/apps/:app_id/releases/:version  # Release detail
POST   /api/v1/apps/:app_id/releases/:version/rollback  # Rollback

# Scaling
GET    /api/v1/apps/:app_id/ps                # Process list with scale
PATCH  /api/v1/apps/:app_id/ps                # Scale processes

# Logs
GET    /api/v1/apps/:app_id/logs              # Recent logs (?lines=100)
GET    /api/v1/apps/:app_id/logs/stream       # WebSocket upgrade for live tail

# Databases (Addons)
GET    /api/v1/databases                      # List all databases
POST   /api/v1/databases                      # Create database
GET    /api/v1/databases/:id                  # Database info
DELETE /api/v1/databases/:id                  # Destroy database
POST   /api/v1/databases/:id/link             # Link to app
DELETE /api/v1/databases/:id/link             # Unlink from app

# Teams
GET    /api/v1/teams
POST   /api/v1/teams
GET    /api/v1/teams/:id/members
POST   /api/v1/teams/:id/members              # Invite
DELETE /api/v1/teams/:id/members/:user_id     # Remove member

# Notifications
GET    /api/v1/notifications                   # List (filterable by app/team)
POST   /api/v1/notifications                   # Create
DELETE /api/v1/notifications/:id               # Remove
```

## Authentication & Token Lifecycle

### Login Flow (CLI & MCP)

1. User runs `wokku login` — prompted for email/password and Wokku API URL
2. CLI sends `POST /api/v1/auth/login` with credentials
3. Server validates via Devise, generates a random token, stores `token_digest` (bcrypt) in `ApiToken` table
4. Returns the plain token to the CLI (only time it's visible)
5. CLI stores token + API URL in `~/.wokku/config`

### Token Properties

- Tokens do not expire by default (personal use convenience), but have an optional `expires_at`
- Users can create multiple named tokens (`wokku auth:token:create --name "ci"`)
- Tokens can be revoked individually or all at once
- `last_used_at` is updated on each API request for audit visibility

### MCP Auth

The MCP server reads the same `~/.wokku/config` file as the CLI. It uses whatever token was stored by `wokku login`. No separate auth flow needed.

## Data Synchronization Strategy

**Dokku is the source of truth.** Wokku's database is a cache/overlay.

### Read-through Pattern

When Wokku displays data (apps list, config vars, domains, etc.), it:
1. Checks if cached data exists and is fresh (< 5 minutes old)
2. If stale or missing, fetches from Dokku via SSH and updates the local DB
3. Returns the fresh data

### Write-through Pattern

When Wokku modifies data (set config, add domain, scale, etc.), it:
1. Executes the Dokku command via SSH
2. If the command succeeds, updates the local DB to match
3. If the command fails, returns the error without updating local DB

### Sync Job

A periodic background job (`SyncServerJob`) runs every 10 minutes per server:
- Fetches `apps:list`, `config:show`, `domains:report`, etc.
- Updates local DB to match Dokku's actual state
- Detects apps/config created directly on Dokku (outside Wokku)
- Marks servers as unreachable if SSH fails

This ensures Wokku stays accurate even if someone modifies Dokku directly via SSH.

## Error Handling & Failure Modes

### SSH Connection Failures

| Scenario | Behavior |
|----------|----------|
| Server unreachable | Mark `Server.status = "unreachable"`, retry 3 times with backoff. Show error in dashboard. |
| SSH auth rejected | Mark `Server.status = "auth_failed"`, notify team admins. |
| Connection drops mid-command | Retry idempotent commands (list, info). Non-idempotent commands (create, destroy) are marked failed and surfaced to user. |

### Deploy Failures

| Scenario | Behavior |
|----------|----------|
| Build fails on Dokku | Deploy.status = "failed", log captured, notification fired. |
| SSH drops mid-deploy | Deploy.status = "failed", partial log saved. User can check Dokku directly. |
| Deploy timeout (> 15 min) | Deploy.status = "timed_out", SSH channel closed, notification fired. |
| Concurrent deploy to same app | Rejected with error — one deploy at a time per app (enforced by DB lock on AppRecord). |

### Server Status States

`Server.status` enum: `connected`, `unreachable`, `auth_failed`, `syncing`

Health check job runs every 5 minutes: attempts SSH connection and runs `dokku version`. Updates status accordingly.

## Monorepo & Packaging Strategy

The project is a monorepo with two publishable artifacts:

1. **Rails app** — deployed as a Docker image or directly via git push
2. **CLI gem** (`wokku-cli`) — published to RubyGems, includes the MCP server

The `cli/` directory has its own gemspec and can be built/published independently. The Rails app does not depend on the CLI gem, and the CLI gem does not depend on Rails — they share only the API contract.

Versioning: both use the same version number, bumped together. The CLI gem version must match a compatible API version.

## Non-Goals (for v1)

- Auto-scaling based on metrics (manual scaling only)
- Built-in CI/CD pipeline
- Marketplace for third-party addons
- Multi-server horizontal scaling per app (each app lives on one server)
- Open-source self-hosted edition (commercial-first, open-source may come later)

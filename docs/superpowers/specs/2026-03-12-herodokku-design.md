# Herodokku Design Spec

**Date:** 2026-03-12
**Status:** Approved

## Overview

Herodokku is a full Heroku-like PaaS built on top of Dokku. It provides a polished web dashboard (Rails 8 + Hotwire), a local CLI (Ruby gem), and an MCP server for AI-assisted infrastructure management via Claude Code.

It communicates with one or more Dokku servers over SSH, giving users a unified interface to manage apps, databases, domains, scaling, logs, and more — without touching Dokku directly.

## Goals

- Recreate the Heroku developer experience on top of Dokku
- Personal use first, potential small-scale commercial offering later
- Self-hostable via Docker Compose, plain VPS, or on Dokku itself
- Pure Ruby stack (Rails + Ruby gem CLI)

## Architecture

```
                         ┌──────────────────┐
┌─────────────┐          │                  │     ┌─────────────────┐
│  herodokku  │───API───▶│                  │─SSH─▶ Dokku Server   │
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
- **Thor-based Ruby gem** for the CLI (`gem install herodokku`)
- **MCP server** in the same gem for Claude Code integration
- **net-ssh** gem to communicate with Dokku servers over the network
- **PostgreSQL** for all persistent data
- **Devise + Pundit** for auth and authorization

### Three Clients, One API

1. **Web dashboard** — Hotwire/Turbo, session auth via Devise
2. **CLI gem** — Thor, token auth via `Authorization: Bearer <token>`
3. **MCP server** — JSON-RPC over stdio, reads auth from `~/.herodokku/config`

All three clients hit the same Rails REST API (`/api/v1/*`).

## Data Model

### Entities

| Model | Purpose | Key Fields |
|-------|---------|------------|
| **User** | Auth, profile | email, password, role |
| **Team** | Group users | name, owner_id |
| **TeamMembership** | User-Team join with role | user_id, team_id, role (admin/member/viewer) |
| **Server** | A Dokku host | name, host, port, ssh_key (encrypted), team_id, status |
| **AppRecord** | A Dokku app ("App" conflicts with Rails) | name, server_id, team_id, status, created_by |
| **Release** | Versioned release (maps to "releases" in CLI) | app_record_id, version (auto-increment), deploy_id (nullable), description, created_at |
| **Deploy** | Deploy execution record | app_record_id, release_id, status (pending/building/succeeded/failed), commit_sha, log, started_at, finished_at |
| **Domain** | Custom domain | app_record_id, hostname, ssl_enabled |
| **EnvVar** | Config/env variable | app_record_id, key, encrypted_value |
| **DatabaseService** | Dokku service (postgres, redis, etc.) | server_id, service_type, name, status |
| **AppDatabase** | Link between app and database | app_record_id, database_service_id, alias (env var name, e.g. DATABASE_URL) |
| **Certificate** | SSL cert | domain_id, expires_at, auto_renew |
| **ProcessScale** | Dyno scaling | app_record_id, process_type (web/worker), count |
| **Notification** | Alert config | app_record_id (nullable), team_id, channel (email/slack/webhook), events, config (JSON) |
| **ApiToken** | Auth token for CLI/MCP | user_id, token_digest (hashed), name, last_used_at, expires_at, revoked_at |
| **SshPublicKey** | User's SSH key for git push auth | user_id, name, public_key, fingerprint |

### Security

- EnvVar values are encrypted at rest (Rails encrypted attributes)
- Server SSH keys are encrypted at rest
- API tokens are hashed (not stored in plain text)

### Relationships

```
User ──▶ TeamMembership ──▶ Team ──▶ Server ──▶ AppRecord
  │                                     │            │
  ├──▶ ApiToken                         ▼            ├──▶ Release ──▶ Deploy
  └──▶ SshPublicKey             DatabaseService      ├──▶ Domain ──▶ Certificate
                                        │            ├──▶ EnvVar
                                        ▼            ├──▶ ProcessScale
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

Values stored encrypted in Herodokku's DB. See "Data Synchronization Strategy" below.

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
Developer                 Herodokku                    Dokku Server
   │                         │                              │
   │  git push herodokku main│                              │
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

Herodokku runs a lightweight Git SSH server on port 2222 using the `sshd` approach (a small Ruby process using `net-ssh` that accepts incoming SSH connections).

**Authentication:** Users register SSH public keys in their Herodokku account (stored in `SshPublicKey` model). The Git SSH server matches the incoming key fingerprint to a Herodokku user. No system-level `authorized_keys` needed.

**Git URL format:** `ssh://herodokku@<herodokku-host>:2222/<app-name>.git`

The `herodokku git:remote -a my-app` CLI command adds this remote automatically.

**Push flow:**
1. Developer pushes to Herodokku git server
2. Server authenticates via SSH public key → resolves to User
3. Server checks Pundit authorization (is this user allowed to deploy this app?)
4. Creates a Release (incrementing version) and Deploy record (status: pending)
5. Receives the git pack data into a temporary bare repo on Herodokku
6. Pushes from the temporary repo to the Dokku server via SSH (`git push dokku main`)
7. Streams Dokku's build output back to the developer AND stores it in Deploy.log
8. Updates Deploy status (succeeded/failed) and broadcasts via Action Cable
9. Fires notification jobs on completion

**Branch handling:** Only pushes to `main` (or the app's configured deploy branch) trigger deploys. Other branches are rejected with a message.

**Rollback:** Herodokku stores the commit SHA for each Release. Rolling back to a previous version re-deploys that commit by doing `dokku git:from-archive` or pushing the tagged commit to Dokku. The rollback creates a new Release record pointing to the old commit.

**Temporary repos** are cleaned up after the deploy completes (success or failure).

### 7. Scaling

| Action | Dokku Command |
|--------|--------------|
| Scale | `ps:scale <app> web=2 worker=3` |
| Report | `ps:report <app>` |

### 8. Metrics/Monitoring

Dokku doesn't provide native metrics. Herodokku polls:
- `docker stats --no-stream --format '{{json .}}'` via SSH for CPU/memory (JSON output for stability across Docker versions)
- `ps:report <app>` for process status

Metrics stored in DB, displayed with Chartkick in the dashboard. Background job polls every 60 seconds per server (not per app, to limit SSH overhead).

**Known limitation:** Polling via SSH has overhead. For production use with many apps, consider installing a lightweight metrics agent (e.g., cAdvisor, Dokku's resource plugin) on Dokku servers. This is a v2 improvement.

### 9. Team/User Management

Handled entirely in Herodokku (not Dokku).

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

## CLI Design

Built with Thor gem, distributed as a Ruby gem (`gem install herodokku`).

Config stored in `~/.herodokku/config` (API URL + auth token). Supports `-a <app>` flag or auto-detection from git remote in current directory.

### Command Reference

```bash
# Auth
herodokku login
herodokku logout
herodokku whoami

# Apps
herodokku apps
herodokku apps:create <name>
herodokku apps:destroy <name>
herodokku apps:info -a <app>
herodokku apps:rename <old> <new>

# Git & Deploys
herodokku git:remote -a <app>
herodokku releases -a <app>
herodokku releases:info <version> -a <app>
herodokku rollback <version> -a <app>

# Config
herodokku config -a <app>
herodokku config:set -a <app> KEY=VAL ...
herodokku config:unset -a <app> KEY ...
herodokku config:get -a <app> KEY

# Domains
herodokku domains -a <app>
herodokku domains:add -a <app> <domain>
herodokku domains:remove -a <app> <domain>
herodokku certs:auto -a <app>

# Addons
herodokku addons -a <app>
herodokku addons:create <type>
herodokku addons:attach <addon> -a <app>
herodokku addons:detach <addon> -a <app>
herodokku addons:destroy <addon>
herodokku addons:info <addon>

# Scaling
herodokku ps -a <app>
herodokku ps:scale -a <app> web=2 worker=3
herodokku ps:restart -a <app>
herodokku ps:stop -a <app>
herodokku ps:start -a <app>

# Logs
herodokku logs -a <app>
herodokku logs -a <app> --tail

# Servers
herodokku servers
herodokku servers:add <name> --host <ip> --key <path>
herodokku servers:remove <name>
herodokku servers:info <name>

# Teams
herodokku teams
herodokku teams:create <name>
herodokku teams:members <team>
herodokku teams:invite <email> <team> --role <role>

# Notifications
herodokku notifications -a <app>
herodokku notifications:add <channel> --url <url>
```

## MCP Server

Ships inside the CLI gem. Launched via `herodokku mcp:start`.

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
    "herodokku": {
      "command": "herodokku",
      "args": ["mcp:start"]
    }
  }
}
```

## Project Structure

```
herodokku/
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
│   ├── herodokku-cli.gemspec
│   ├── lib/herodokku/
│   │   ├── cli.rb                    # Thor main
│   │   ├── commands/                 # Subcommands
│   │   ├── api_client.rb
│   │   └── config_store.rb
│   ├── mcp/
│   │   ├── server.rb
│   │   └── tools/
│   └── exe/herodokku
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
    command: bundle exec herodokku git:server
    ports: ["2222:2222"]
  db:
    image: postgres:16
  redis:
    image: redis:7
```

### On Dokku

```bash
dokku apps:create herodokku
dokku postgres:create herodokku-db
dokku postgres:link herodokku-db herodokku
dokku config:set herodokku SECRET_KEY_BASE=... DOKKU_SSH_KEY=...
dokku ports:add herodokku tcp:2222:2222
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

1. User runs `herodokku login` — prompted for email/password and Herodokku API URL
2. CLI sends `POST /api/v1/auth/login` with credentials
3. Server validates via Devise, generates a random token, stores `token_digest` (bcrypt) in `ApiToken` table
4. Returns the plain token to the CLI (only time it's visible)
5. CLI stores token + API URL in `~/.herodokku/config`

### Token Properties

- Tokens do not expire by default (personal use convenience), but have an optional `expires_at`
- Users can create multiple named tokens (`herodokku auth:token:create --name "ci"`)
- Tokens can be revoked individually or all at once
- `last_used_at` is updated on each API request for audit visibility

### MCP Auth

The MCP server reads the same `~/.herodokku/config` file as the CLI. It uses whatever token was stored by `herodokku login`. No separate auth flow needed.

## Data Synchronization Strategy

**Dokku is the source of truth.** Herodokku's database is a cache/overlay.

### Read-through Pattern

When Herodokku displays data (apps list, config vars, domains, etc.), it:
1. Checks if cached data exists and is fresh (< 5 minutes old)
2. If stale or missing, fetches from Dokku via SSH and updates the local DB
3. Returns the fresh data

### Write-through Pattern

When Herodokku modifies data (set config, add domain, scale, etc.), it:
1. Executes the Dokku command via SSH
2. If the command succeeds, updates the local DB to match
3. If the command fails, returns the error without updating local DB

### Sync Job

A periodic background job (`SyncServerJob`) runs every 10 minutes per server:
- Fetches `apps:list`, `config:show`, `domains:report`, etc.
- Updates local DB to match Dokku's actual state
- Detects apps/config created directly on Dokku (outside Herodokku)
- Marks servers as unreachable if SSH fails

This ensures Herodokku stays accurate even if someone modifies Dokku directly via SSH.

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
2. **CLI gem** (`herodokku-cli`) — published to RubyGems, includes the MCP server

The `cli/` directory has its own gemspec and can be built/published independently. The Rails app does not depend on the CLI gem, and the CLI gem does not depend on Rails — they share only the API contract.

Versioning: both use the same version number, bumped together. The CLI gem version must match a compatible API version.

## Non-Goals (for v1)

- Multi-region deployment
- Built-in CI/CD pipeline
- Marketplace for third-party addons
- Billing/payments system
- Auto-scaling based on metrics

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
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  herodokku  │────▶│                  │────▶│  Dokku Server   │
│  CLI (gem)  │ API │  Rails API/Web   │ SSH │  (one or many)  │
└─────────────┘     │  (Hotwire/Turbo) │     └─────────────────┘
                    │                  │
│  Claude Code │    │  PostgreSQL      │
│  via MCP     │───▶│  Action Cable    │
└──────────────┘    │  Solid Queue     │
                    └──────────────────┘
 Browser ──────────▶        ▲
```

### Key Technology Choices

- **Rails 8** with Hotwire/Turbo/Stimulus for the dashboard (no separate frontend)
- **Action Cable** for real-time log streaming and deploy progress
- **Solid Queue** for background jobs (deploys, SSH commands, health checks)
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
| **Deploy** | Deploy history | app_record_id, status, commit_sha, log, started_at, finished_at |
| **Domain** | Custom domain | app_record_id, hostname, ssl_enabled |
| **EnvVar** | Config/env variable | app_record_id, key, encrypted_value |
| **DatabaseService** | Dokku service (postgres, redis, etc.) | server_id, service_type, name, status |
| **AppDatabase** | Link between app and database | app_record_id, database_service_id |
| **Certificate** | SSL cert | domain_id, expires_at, auto_renew |
| **ProcessScale** | Dyno scaling | app_record_id, process_type (web/worker), count |
| **Notification** | Alert config | team_id, channel (email/slack/webhook), events, config (JSON) |

### Security

- EnvVar values are encrypted at rest (Rails encrypted attributes)
- Server SSH keys are encrypted at rest
- API tokens are hashed (not stored in plain text)

### Relationships

```
User ──▶ TeamMembership ──▶ Team ──▶ Server ──▶ AppRecord
                                        │            │
                                        ▼            ├──▶ Deploy
                                  DatabaseService    ├──▶ Domain ──▶ Certificate
                                        │            ├──▶ EnvVar
                                        ▼            └──▶ ProcessScale
                                   AppDatabase
                                  (links apps ↔ dbs)
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
| Info | `apps:report <name>` |

### 2. Environment Variables

| Action | Dokku Command |
|--------|--------------|
| Set | `config:set <app> KEY=VAL` |
| Unset | `config:unset <app> KEY` |
| List | `config:show <app>` |

Values stored encrypted in Herodokku's DB and synced to Dokku.

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

Herodokku runs a lightweight Git SSH server (port 2222). Users push to Herodokku, which forwards to Dokku, tracking deploy history and streaming logs back.

### 7. Scaling

| Action | Dokku Command |
|--------|--------------|
| Scale | `ps:scale <app> web=2 worker=3` |
| Report | `ps:report <app>` |

### 8. Metrics/Monitoring

Dokku doesn't provide native metrics. Herodokku polls:
- `docker stats <container>` via SSH for CPU/memory
- `ps:report <app>` for process status

Metrics stored in DB, displayed with Chartkick in the dashboard. Background job polls every 30-60 seconds.

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

Configurable per-team, per-event (deploy success, deploy failure, app crash).

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
    command: bundle exec solid_queue:start
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

## Non-Goals (for v1)

- Multi-region deployment
- Built-in CI/CD pipeline
- Marketplace for third-party addons
- Billing/payments system
- Auto-scaling based on metrics

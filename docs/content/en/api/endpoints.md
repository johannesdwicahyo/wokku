---
title: API Endpoints
summary: A short index of the REST API by task. The OpenAPI spec is the full reference.
eyebrow: api
last_updated: 2026-11-07
---

Find the endpoint you need, then look up its parameters and responses in the full spec.

- **Base URL:** `https://wokku.cloud/api/v1`
- **Auth:** `Authorization: Bearer <token>` — see [Authentication](/docs/api/authentication)
- **Full reference:** [`/api/v1/openapi.yaml`](https://wokku.cloud/api/v1/openapi.yaml) (OpenAPI 3; load it into Postman, Insomnia or a client generator)

Paths below are relative to the base URL. App and database paths accept an ID or a name.

:::callout note
Creating an app (`POST /apps`) needs a `server_id`. Take the `id` from `GET /servers`. The dashboard, CLI and Claude Code fill this in for you.
:::

## Apps

| Method | Path | What it does |
|---|---|---|
| GET, POST | `/apps` | List apps, create an app |
| GET, PATCH, DELETE | `/apps/:id` | Show, update or delete an app |
| POST | `/apps/:id/restart`, `/stop`, `/start` | Restart, stop or start |
| PATCH | `/apps/:id/rename` | Rename |
| POST | `/apps/:id/clone` | Copy settings into a new app |
| POST | `/apps/:id/lock`, `/unlock` | Block or allow deploys |
| PATCH | `/apps/:id/https`, `/cdn`, `/maintenance` | HTTPS redirect, CDN proxy, maintenance mode |
| POST | `/apps/:id/transfer` | Offer the app to another user |
| GET | `/app_transfers` | List transfers |
| POST, DELETE | `/app_transfers/:id/accept`, `/decline`, `/app_transfers/:id` | Accept, decline or cancel |

## Deploys and releases

| Method | Path | What it does |
|---|---|---|
| POST | `/apps/:id/deploy` | Redeploy the latest source |
| GET, POST | `/apps/:app_id/deploys` | List deploys, start one |
| GET | `/apps/:app_id/deploys/:id` | Show a deploy and its log |
| POST | `/apps/:app_id/deploys/uploads` | Upload a source archive to deploy |
| GET | `/apps/:app_id/releases`, `/releases/:id` | List or show releases |
| POST | `/apps/:app_id/releases/:id/rollback` | Roll back |
| POST | `/ai/diagnose` | AI diagnosis of a failed deploy |
| POST, DELETE | `/apps/:id/github_connect`, `/github_disconnect` | Connect or disconnect GitHub |
| GET | `/github/repos` | Repos the Wokku GitHub App can see |
| GET, DELETE | `/apps/:app_id/previews`, `/previews/:pr_number` | List or remove PR previews |
| PATCH | `/apps/:id/preview_settings` | Preview on/off and database choice |

## Config, processes and tasks

| Method | Path | What it does |
|---|---|---|
| GET, PATCH, DELETE | `/apps/:app_id/config` | Read, set or unset env vars |
| GET, PATCH | `/apps/:app_id/ps` | Show or scale processes |
| GET, PATCH | `/apps/:app_id/dynos`, `/dynos/:id` | Process sizes; resize a process type |
| GET | `/dyno_tiers` | Available sizes and prices |
| POST | `/apps/:id/run` | Start a one-off command |
| GET | `/apps/:app_id/runs/:id` | Check a one-off run |
| GET, POST, DELETE | `/apps/:app_id/scheduled_tasks`, `/scheduled_tasks/:id` | Scheduled tasks |
| POST, DELETE | `/apps/:app_id/dev_sessions`, `/dev_sessions/:id` | Local dev sessions |

## Domains

| Method | Path | What it does |
|---|---|---|
| GET, POST | `/apps/:app_id/domains` | List or add (`{"hostname": "…"}`) |
| DELETE | `/apps/:app_id/domains/:id` | Remove |
| POST | `/apps/:app_id/domains/:id/ssl` | Issue a certificate |

## Logs and monitoring

| Method | Path | What it does |
|---|---|---|
| GET | `/apps/:app_id/logs` | Logs (`lines`, `since`, `until`, `level`, `q`) |
| GET | `/apps/:id/metrics`, `/monitor`, `/vitals` | CPU/memory, request stats, Web Vitals |
| POST | `/apps/:id/vitals/rotate_token` | New web-vitals token |
| GET | `/apps/:app_id/checks` | Health check status |
| GET | `/incidents`, `/incidents/:id` | Outages |
| GET, POST, DELETE | `/alert_mutes`, `/alert_mutes/:id` | Phone alert mutes |
| GET, POST, DELETE | `/notifications`, `/notifications/:id` | Notification channels |
| POST | `/notifications/:id/test` | Send a test message |
| GET | `/activities` | Activity feed (`limit`, max 200) |
| GET | `/doctor` | Self-check of token, client and apps |

## Add-ons and databases

| Method | Path | What it does |
|---|---|---|
| GET | `/apps/:app_id/addons` | List an app's add-ons |
| POST, DELETE | `/apps/:app_id/addons/shared`, `/shared/:engine` | Add or remove a free shared add-on |
| POST | `/apps/:app_id/addons/dedicated` | Upgrade to a dedicated add-on |
| DELETE | `/apps/:app_id/addons/:id` | Remove a dedicated add-on |
| GET, POST | `/databases` | List or create databases |
| GET, DELETE | `/databases/:id` | Show or delete |
| POST | `/databases/:id/link`, `/unlink` | Link to or unlink from an app |
| PATCH | `/databases/:id/resize` | Resize a dedicated database |
| POST | `/databases/:id/import`, `/retry` | Import a dump; retry provisioning |
| GET | `/databases/:id/monitor` | Connections, cache hit, size, queries |
| GET, POST | `/databases/:database_id/backups` | List backups, back up now |
| GET | `/databases/:database_id/backups/:id/download` | Download link |
| POST | `/databases/:database_id/backups/:id/restore` | Restore |

## Templates

| Method | Path | What it does |
|---|---|---|
| GET | `/templates`, `/templates/:id` | List or show templates |
| POST | `/templates/deploy` | Deploy a template |

## Account and teams

| Method | Path | What it does |
|---|---|---|
| GET | `/auth/whoami` | Current user |
| GET, POST, DELETE | `/auth/tokens`, `/auth/tokens/:id` | API tokens |
| POST | `/auth/device/code`, `/auth/device/token` | Browser sign-in for tools |
| GET, POST, DELETE | `/ssh_keys`, `/ssh_keys/:id` | SSH keys |
| GET, POST | `/teams` | List or create teams |
| GET, POST, PATCH, DELETE | `/teams/:team_id/members`, `/members/:id` | Team members and roles |
| POST, DELETE | `/devices`, `/devices/:id` | Register a phone for push alerts |
| POST | `/account/deletion` | Delete your account |
| GET | `/servers` | Servers you can deploy to (for `server_id`) |
| GET | `/meta` | API and minimum client versions (no auth) |

## Billing

| Method | Path | What it does |
|---|---|---|
| GET | `/billing/current_plan` | Your plan and limits |
| GET | `/billing/invoices` | Invoices |

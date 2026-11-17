# Wokku

**An open-source, self-hostable Heroku alternative.** Deploy apps with
`git push`, install open-source tools in one click, and manage databases,
domains, SSL, cron, logs, and metrics from one dashboard — on your own
server.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Rails](https://img.shields.io/badge/Rails-8.1-CC0000.svg)](https://rubyonrails.org)
[![Go](https://img.shields.io/badge/wokkud-Go-00ADD8.svg)](wokkud/)

> **Status: early.** The one-command install is tested on fresh budget
> VPSes and the same engine runs [wokku.cloud](https://wokku.cloud) in
> production — but this is a young open-source project. Expect rough edges
> and please [open issues](https://github.com/johannesdwicahyo/wokku/issues).

## Features

- **Git push deploys** — `git push wokku main` builds with
  [nixpacks](https://nixpacks.com) or your own Dockerfile and ships to
  Docker Swarm. Real-time build logs in the browser.
- **100+ one-click templates** — Ghost, Umami, Appwrite, Authentik, n8n,
  Baserow, and many more open-source tools, deployed with sane defaults.
- **Databases** — PostgreSQL, MySQL, MariaDB, Redis, and MongoDB, each in
  its own container on your server, linked to apps with one click.
- **Automatic HTTPS** — Caddy owns routing and TLS; every app gets a
  certificate out of the box, custom domains included. Works with zero
  DNS setup via `<ip>.sslip.io`.
- **Encrypted backups** — nightly, encrypted database backups to any
  S3-compatible bucket (AWS S3, Cloudflare R2, Backblaze B2, MinIO, …),
  with retention and one-click restore. Set the bucket in admin → servers
  → backups.
- **Scheduled tasks** — cron jobs defined in the dashboard, executed on
  the host by the agent.
- **Logs, metrics, and web vitals** — persisted searchable logs,
  CPU/memory charts, request metrics, and real-user Core Web Vitals.
- **Browser terminal** — SSH into your servers and app containers from
  the dashboard (xterm.js).
- **Rollbacks** — every deploy keeps an image; roll back from the UI.
- **Teams and 2FA** — role-based team access and two-factor login (set
  `WOKKU_REQUIRE_ADMIN_2FA=1` to make it mandatory for the admin).
- **GitHub integration** — connect a repo for automatic deploys on push.
- **REST API** — everything the dashboard does, with an OpenAPI spec at
  `/api/v1/openapi.yaml`. (The `wokku` CLI and MCP server currently talk
  to wokku.cloud only; self-host support is planned.)
- **Multi-server** — connect additional servers with a one-line command;
  one dashboard, your whole fleet.

## Get started

One command on a fresh Ubuntu 22.04+ or Debian 11+ box (x86_64, 2 GB RAM, 10 GB free disk):

```sh
curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/install.sh | sudo bash
```

It starts the control plane (docker compose), installs the app runtime on
the same box (Docker Swarm, local registry, Caddy, nixpacks, the wokkud
agent), and serves the dashboard on 80/443 with a real certificate via
`<ip>.sslip.io` — no DNS needed. Open the printed URL, create your admin
account, deploy. Connect additional servers from admin → servers.

### Run the pieces yourself

Prefer compose (also works locally on macOS/Windows with Docker
Desktop or OrbStack):

```sh
SECRET_KEY_BASE=$(openssl rand -hex 64) docker compose up
# open http://localhost:3000 — the first visit asks you to create
# your admin account
```

The web container migrates (baseline schema), seeds the product rows, and
serves on :3000. Connect a server from the admin UI to run apps — the
wokkud agent installs onto it.

Forgot the admin password?

```sh
docker compose run web bin/rails runner \
  'User.find_by(role: :admin).update!(password: "new-strong-password")'
```

### Your first deploy

The first deploy on a new server downloads the build images (Node, Python,
… base layers), so it takes a few minutes — longer on a slow connection.
The installer starts that download in the background right away; once it
is done, deploys take about a minute.

### Updating

Re-run the installer — it keeps your data and settings, pulls the newest
image, restarts the dashboard (apps keep running) and updates the agent:

```sh
cd /opt/wokku && sudo bash install.sh
```

The dashboard checks for a new release once a day (an anonymous read of the
public image's version label — nothing about your install is sent). When one
is out, admins see a banner and the admin gets one email per release. Turn
it off with `WOKKU_UPDATE_CHECK=0` in `.env`.

### Backups

Databases are backed up nightly once you add a bucket in admin → servers →
backups (any S3-compatible provider; saving tests the connection). Backups
are encrypted with a key the installer writes to `/opt/wokku/.env` as
`WOKKU_BACKUP_PRIVATE_KEY`. **Keep a copy of `.env` somewhere safe** —
without that key, backups can't be restored.

### Email

Password resets, team invites and alerts need an SMTP server. Uncomment the
`SMTP_*` lines in `/opt/wokku/.env` (any provider works), then
`cd /opt/wokku && docker compose up -d`. Without SMTP the dashboard works but
sends no email.

### Budget VPS with a shared public IP

Some providers share one public IPv4 between many VPSes (you SSH in on a
high port, and the server has a private address). Their proxy routes ports
80/443 by domain, so add your dashboard domain (e.g. `<ip>.sslip.io`) in the
provider's panel — the installer warns when the domain doesn't reach the
server. Re-add it after reinstalling the OS.

**Notes:** the bundled Postgres works out of the box; external/managed
Postgres needs privileges for `CREATE EXTENSION pgcrypto`.

## Don't want to host it yourself?

[wokku.cloud](https://wokku.cloud) is the managed cloud: same engine, same
UI, with billing, managed infrastructure, and Indonesian payment methods
(QRIS, bank transfer, IDR) on top. Using it funds this project.

## What's in this repository

| Path | What it is |
|------|------------|
| `app/`, `config/`, `lib/`, `wokku.gemspec` | **The Wokku engine** — a mountable Rails engine carrying the whole product surface: dashboard UI, REST API, models, jobs, services, and in-app docs. |
| `wokkud/` | **The host agent** (Go) — claims typed lifecycle/service operations from the control plane and executes them on your server: builds, Swarm converges, database provisioning, cron, metrics. |
| `harness/` | A minimal Rails host app that boots the engine standalone with the open-source null providers — what CI and the self-host image run. |
| `install.sh` | The one-command installer. |

The managed cloud runs this exact engine and layers billing and managed
infrastructure on top via provider injection (`Wokku.configure`) —
open-source and managed share one codebase, one UI, one test suite
(4,000+ examples, 95% line coverage enforced in CI).

**How a deploy works:** the control plane writes a typed operation row;
the wokkud agent on your server claims it, builds the image, converges
the Swarm service, and reports back via heartbeat. Caddy picks up routes
and certificates. No SSH from the control plane for the hot path.

## Documentation

Guides live in the dashboard at `/docs` (English + Bahasa Indonesia) and
online at [wokku.cloud/docs](https://wokku.cloud/docs).

## Support

- [GitHub Issues](https://github.com/johannesdwicahyo/wokku/issues) —
  bugs and feature requests

## Contributing

Pull requests welcome — see [CONTRIBUTING](CONTRIBUTING.md).
Contributions require agreeing to the [CLA](CLA.md).

## License

[AGPL-3.0-or-later](LICENSE)

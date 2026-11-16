# Wokku

**An open-source, self-hostable Heroku alternative.** Deploy apps with
`git push`, install open-source tools in one click, and manage databases,
domains, SSL, cron, logs, and metrics from one dashboard — on your own
server.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Rails](https://img.shields.io/badge/Rails-8.1-CC0000.svg)](https://rubyonrails.org)
[![Go](https://img.shields.io/badge/wokkud-Go-00ADD8.svg)](wokkud/)

> **Status: pre-release.** The engine split landed recently; the self-host
> story (installer, server connect, docs) is actively being built. Watch
> releases.

## Features

- **Git push deploys** — `git push wokku main` builds with
  [nixpacks](https://nixpacks.com) or your own Dockerfile and ships to
  Docker Swarm. Real-time build logs in the browser.
- **137 one-click templates** — Ghost, Umami, Appwrite, Authentik, n8n,
  Baserow, and 130+ more open-source tools, deployed with sane defaults.
- **Managed databases** — dedicated PostgreSQL, Redis, MariaDB, and
  MongoDB, plus shared PostgreSQL/Redis/Memcached/RabbitMQ/Meilisearch
  for lighter workloads. Linked to apps with one click.
- **Automatic HTTPS** — Caddy owns routing and TLS; every app gets a
  certificate out of the box, custom domains included. Works with zero
  DNS setup via `<ip>.sslip.io`.
- **Encrypted backups** — envelope-encrypted database backups with
  retention policies and automated restore drills.
- **Scheduled tasks** — cron jobs defined in the dashboard, executed on
  the host by the agent.
- **Logs, metrics, and web vitals** — persisted searchable logs,
  CPU/memory charts, request metrics, and real-user Core Web Vitals.
- **Browser terminal** — SSH into your servers and app containers from
  the dashboard (xterm.js).
- **Rollbacks** — every deploy keeps an image; roll back from the UI.
- **Teams and 2FA** — role-based team access; admin accounts require
  two-factor.
- **GitHub integration** — connect a repo for automatic deploys on push.
- **API, CLI, and MCP** — a full REST API, the `wokku` CLI, and an MCP
  server so AI agents can deploy and operate apps.
- **Multi-server** — connect additional servers with a one-line command;
  one dashboard, your whole fleet.

## Get started

One command on a fresh Ubuntu 22.04/24.04 or Debian 11+ box:

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
(2,900+ examples, 95% line coverage enforced in CI).

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

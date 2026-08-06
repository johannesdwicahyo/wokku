# Wokku

Open-source PaaS: deploy apps with `git push`, manage databases, domains,
SSL, cron, logs, and metrics from a dashboard. Runs on your own server via
the **wokkud** host agent (Go) + Docker Swarm, with Caddy handling
routing/TLS.

This repository contains:

- **The Wokku core engine** (`app/`, `config/`, `lib/`, `wokku.gemspec`) —
  a mountable Rails engine carrying the product surface: dashboard UI, API,
  models, jobs, and services. (Route mounting for the full dashboard/API
  lands in an upcoming phase — today the engine boots standalone but most
  routes are still drawn by the host application.)
- **wokkud** (`wokkud/`) — the host agent that executes typed lifecycle and
  service operations on your server.
- **harness/** — a minimal Rails host application used by CI to boot the
  engine standalone (with the open-source null providers).

The managed cloud at [wokku.cloud](https://wokku.cloud) runs this same
engine and layers billing, tunnels, and managed infrastructure on top via
provider injection (`Wokku.configure`) — open-source and managed share one
codebase, one UI.

## Self-host (pre-release)

One command on a fresh Ubuntu/Debian box:

```sh
curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/install.sh | sudo bash
```

It starts the control plane (docker compose), installs the app runtime on
the same box (Docker Swarm, local registry, Caddy, nixpacks, wokkud
agent), and serves the dashboard on 80/443 with a real certificate via
`<ip>.sslip.io` — no DNS needed. Open the printed URL; the first visit
asks you to create your admin account, then deploy. Connect ADDITIONAL
servers with the one-line command under admin → servers.

Prefer to run the pieces yourself?

```sh
SECRET_KEY_BASE=$(openssl rand -hex 64) docker compose up
# open http://localhost:3000 — the first visit asks you to create
# your admin account
```

The web container migrates (baseline schema), seeds the product rows,
and serves on :3000. Connect a server from the admin
UI to run apps — the wokkud agent installs onto it.

Forgot the admin password? Reset it:

```sh
docker compose run web bin/rails runner \
  'User.find_by(role: :admin).update!(password: "new-strong-password")'
```

Notes: the bundled Postgres works out of the box; external/managed
Postgres needs privileges for `CREATE EXTENSION pgcrypto`. Recurring
job schedules (metrics collectors, retention sweeps) are not yet wired
for self-host — tracked for the next release.

> **Status: pre-release.** The engine split landed recently; the
> self-host installation story (docker-compose, server connect, docs) is
> actively being built. Watch releases.

## License

[AGPL-3.0-or-later](LICENSE). Contributions require agreeing to the
[CLA](CLA.md) — see [CONTRIBUTING](CONTRIBUTING.md).

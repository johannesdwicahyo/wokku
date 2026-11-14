---
title: Self-Hosting
summary: Run the open-source Wokku engine on your own server with one install script.
last_updated: 2026-11-07
---

Install Wokku on your own Ubuntu or Debian server and get the same dashboard you use on Wokku Cloud.

:::callout note
The Wokku source repository isn't public yet. These steps work once you have a copy of it; this page will link the repository when it's published.
:::

## What you get

Self-hosted Wokku is the same engine that runs Wokku Cloud:

| Included | |
|---|---|
| Dashboard and REST API | ✓ |
| `git push` deploys (your Dockerfile, or Nixpacks auto-detect) | ✓ |
| Automatic HTTPS and custom domains (Caddy) | ✓ |
| One-click apps | ✓ |
| Databases — shared and dedicated | ✓ |
| Scheduled tasks, logs, metrics, rollbacks | ✓ |
| GitHub auto-deploy | ✓ |
| Workspaces, members and roles | ✓ |
| More servers in one dashboard | ✓ |

What's different from Wokku Cloud:

- **No billing.** There are no prices, plans or limits.
- **No automatic DNS.** You point your own domains.
- **The `wokku` CLI, the Claude Code plugin and the iOS & Mac apps only talk to wokku.cloud.** Use the dashboard or the REST API on your install.
- **Sign-up is closed by default.** You create the admin account on first visit; others can't register unless you allow it.

## Requirements

- A fresh **Ubuntu 22.04/24.04** or **Debian 11+** server, x86_64
- Ports **80** and **443** open
- `sudo` access

## Install

1. Put a copy of the Wokku repository at `/opt/wokku` on the server.
2. Run the installer:
   ```bash
   sudo bash /opt/wokku/install.sh
   ```
3. Open the URL it prints (`https://<your-ip>.sslip.io`) and create your admin account.

The installer sets up Docker, starts the control plane, and installs the app runtime (Docker Swarm, a local registry, Caddy, Nixpacks and the `wokkud` agent) on the same box. The server registers itself as your first server. `<ip>.sslip.io` gives you a working HTTPS address without any DNS setup.

The script is safe to re-run.

## Settings

Set these in `/opt/wokku/.env`, then run `docker compose up -d` in `/opt/wokku`:

| Variable | What it does |
|---|---|
| `WOKKU_CANONICAL_DOMAIN` | The domain apps live under (`<app>.<domain>`). Defaults to `<ip>.sslip.io`. Point a wildcard DNS record at the server before changing it. |
| `WOKKU_OPEN_REGISTRATION=1` | Let anyone sign up. Off by default. |
| `WOKKU_REQUIRE_ADMIN_2FA=1` | Force admins to set up 2FA. Off by default. |

## Update

Re-run the installer. It pulls the latest code and rebuilds:

```bash
sudo bash /opt/wokku/install.sh
```

## Add more servers

See [Connect a Server](/docs/oss/connect-server).

## Reset the admin password

```bash
cd /opt/wokku
docker compose run web bin/rails runner \
  'User.find_by(role: :admin).update!(password: "new-strong-password")'
```

## License

AGPL-3.0-or-later. You can run it for yourself, your team or your company. If you offer a modified version as a hosted service, you must publish your changes. For other licensing, email [hello@wokku.cloud](mailto:hello@wokku.cloud).

Don't want to run servers? [Wokku Cloud](https://wokku.cloud) runs this engine for you.

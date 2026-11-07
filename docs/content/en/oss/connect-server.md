---
title: Connect a Server
summary: Add another server to your self-hosted Wokku so apps can run on it.
last_updated: 2026-11-07
---

Add a second (or third) server to a self-hosted Wokku install. On Wokku Cloud you never do this — we run the servers.

Your first server is connected for you by the [installer](/docs/oss/overview).

## Steps

1. As an admin, open **Servers** in the dashboard sidebar and add a server: a name and its IP address or hostname.
2. The server's page shows a one-line install command with a secret token. Copy it.
3. On the new server, as a user with `sudo`, run it. It looks like:
   ```bash
   curl -sSL https://<your-wokku>/install/wokkud.sh | sudo bash -s -- <token>
   ```
4. Wait about 30 seconds. The server page switches to **connected** on the agent's first check-in.

The script secures the host (security updates, firewall, fail2ban) and installs the Wokku agent. Add `--no-harden` to the end of the command to skip the hardening.

:::callout warning
The token in the command is the server's secret. Don't share it or paste it anywhere public.
:::

## How it connects

The agent on the new server talks to your control plane over HTTPS — deploys don't need SSH. The SSH fields on the server form are only used for reading logs and stats from the host.

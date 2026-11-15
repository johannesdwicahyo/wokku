---
title: Production Readiness
summary: Keep state out of the container, shut down cleanly, and size your app so deploys and resizes don't surprise you.
last_updated: 2026-11-07
---

You'll check the few things that keep a production app healthy through deploys, restarts and resizes.

## Pick a size that stays awake

Free apps sleep after 30 minutes without traffic and take about 30 seconds to wake on the next request. That's fine for experiments. For anything people rely on, give the app paid CPU and RAM so it stays on. See [Resources](/docs/scaling/resources) and [Pricing](/docs/billing/pricing).

## Keep state out of the container

Every deploy, restart and resize replaces the container, and its local disk goes with it.

| Where data lives | Survives a deploy? |
|------------------|--------------------|
| A database add-on (Postgres, MySQL, MariaDB, MongoDB, Redis) | Yes |
| The container's own disk (`/tmp`, `./uploads`, an on-disk SQLite file) | **No** |

:::callout warning
User uploads in a local folder or an on-disk SQLite database are lost on the next deploy. Put state in a [database](/docs/databases/create-link) or external object storage.
:::

## Shut down cleanly

When a container is replaced, your process gets `SIGTERM`, then `SIGKILL` after a short grace period.

- Web servers should finish in-flight requests and exit.
- Background jobs that are still running get killed. Make jobs idempotent so a retry is safe, and break long jobs into smaller steps.

Restarting or resizing an app restarts **all** its process types, so a web resize also restarts your workers.

## Health

The platform supervises your containers: on deploy the new container starts before the old one stops, and a crashed container restarts automatically. Configurable health checks are coming soon. See [Health Checks](/docs/monitoring/health-checks).

## Resize safely

- Sizing **up** is safe.
- Sizing **down** below what the app actually uses can get it killed for running out of memory on boot. Check [Metrics](/docs/monitoring/metrics) first.
- Resize before a traffic spike, not during it.

## Checklist

- [ ] The app runs on a paid size, not the free sleeping one
- [ ] No important data is written to the container's disk
- [ ] Migrations run with `wokku run my-app -- <migrate command>` after each deploy
- [ ] Background jobs are idempotent and handle `SIGTERM`
- [ ] Memory use is below the new size before you downsize

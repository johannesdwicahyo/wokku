---
title: Production Readiness
summary: "What separates a hobby deploy from a production one: a health check, persistent storage for state, graceful shutdown, and resizing without surprises."
eyebrow: apps
last_updated: 2026-06-06
---

# Production Readiness

Getting an app to deploy is the easy part. Keeping it healthy through deploys, restarts, and box resizes takes four things: a **health check**, **persistent storage** for anything you can't lose, **graceful shutdown** for background work, and an understanding of what a **resize** actually does to your container.

This page covers all four. If you only do one thing, add a health check.

:::callout note
A *box* is one container (what others call a "dyno"). See [Box Tiers](/docs/scaling/tiers) for sizes and [Plans](/docs/billing/plans) for how many you can run.
:::

## The one-line rule

- **Hobby / experiments** → a Sleeping box is fine. It idles to sleep and wakes on the next request (with a cold-start delay).
- **Production** → a paid (always-on) box **+ a health check** + persistent storage for any state. Never run something you care about on a Sleeping box.

---

## Health checks (reference)

A health check is an HTTP request Wokku makes to your app to confirm it's actually ready to serve traffic — not just that the process started. It's the single most important production setting because it gates **zero-downtime** behavior.

### Why it matters

During a deploy, restart, or **box resize**, Wokku does not mutate the running container in place. It starts a **brand-new** container and has to decide when to send traffic to it.

- **With a health check:** Wokku boots the new container, polls your check path until it passes, *then* switches traffic over, and only after that retires the old container. In-flight requests drain to the old container during the retire window. Result: **no downtime**.
- **Without a health check:** Wokku can't tell when the new container is ready, so it switches as soon as the process is up. If your app needs a few seconds to boot (framework load, DB connections, cache warm), requests in that window get a **brief error or stall** — typically 1–5s. This is exactly why a resize "blips" on apps with no check.

:::callout warn
A box **resize** is a container recreation — it has the same readiness semantics as a deploy. No health check means every resize and restart risks a short blip. Add one before you scale for a traffic spike, not during it.
:::

### The knobs

Wokku exposes four settings (configure them under your app → **Health Checks**, or see [Health Checks](/docs/monitoring/health-checks) for the CLI/API/MCP equivalents):

| Setting | Key | Default | What it controls |
|---------|-----|---------|------------------|
| **Path** | `CHECKS_PATH` | `/` | The HTTP path polled. Point this at a lightweight endpoint that returns `200` only when the app is truly ready (e.g. `/up`). |
| **Wait** | `CHECKS_WAIT` | `5` | Seconds to wait after the container starts **before** the first check — warm-up grace for slow boots. |
| **Timeout** | `CHECKS_TIMEOUT` | `30` | Seconds to wait for each individual check request to respond. |
| **Attempts** | `CHECKS_ATTEMPTS` | `5` | How many times to retry a failing check before declaring the deploy failed (and rolling back). |

There is also a **wait-to-retire** window (default **60s**): after traffic switches to the new container, the old one is kept alive briefly so in-flight requests can finish before it's removed.

So a slow-booting app gets, by default: `WAIT (5s)` warm-up, then up to `ATTEMPTS (5) × TIMEOUT (30s)` of polling before the deploy is failed. Increase `WAIT` and `ATTEMPTS` for apps that take a long time to become ready rather than disabling checks.

### Choosing a check endpoint

The default path is `/`, but `/` is often heavy (renders your homepage, hits the DB). Prefer a dedicated, cheap endpoint that returns `200` only when dependencies are reachable.

Rails ships one out of the box at **`/up`** (`Rails::HealthController`), which is why you'll see `/up` throughout these docs. For other frameworks, add a trivial route:

```ruby
# Rails — already provided at /up by default:
#   get "up" => "rails/health#show"
```

```javascript
// Express
app.get("/up", (_req, res) => res.sendStatus(200))
```

```python
# Flask
@app.get("/up")
def up():
    return "", 200
```

Keep the endpoint **dependency-aware but cheap**: a `200` should mean "I can serve requests," but it shouldn't run an expensive query on every poll.

### Defining checks in your repo

Two repo-level options, in addition to the dashboard settings above:

- **`app.json`** (recommended) — add a `healthcheck` block so the check travels with your code:
  ```json
  {
    "healthcheck": { "path": "/up", "wait": 5, "timeout": 30, "attempts": 5 }
  }
  ```
- **`CHECKS` file** — a legacy plain-text file in your app root listing paths (and optional expected response text) to verify. Use `app.json` for new apps.

Dashboard settings and repo files combine; repo definitions make the check reproducible across environments.

### Disabling checks

You *can* disable checks for an app that genuinely can't expose an HTTP endpoint quickly — but this removes zero-downtime protection entirely. Prefer raising `WAIT`/`ATTEMPTS` first.

---

## Persistent vs ephemeral storage

The container filesystem is **ephemeral**. Every deploy, restart, and resize **destroys the old container and its local disk**. Anything written inside the container that isn't on a mounted volume is gone.

| Where you wrote it | Survives deploy/restart/resize? |
|--------------------|---------------------------------|
| A managed addon (Postgres, MySQL, Mongo, Redis, MinIO) | ✅ Yes — separate service |
| A path on a `storage:mount` volume | ✅ Yes — host-backed volume |
| The container's local fs (`/tmp`, `./uploads`, on-disk SQLite) | ❌ **No — wiped on every recreate** |

:::callout danger
If your app saves user uploads to a local folder, stores an on-disk SQLite database, or keeps any state on the container filesystem, **that data is lost on your next deploy or resize**. Move it to a database/object-storage addon, or mount persistent storage for that path.
:::

Rule of thumb: **real state belongs in an addon.** Use a mounted volume only for things that must be a file on disk. Treat the container as disposable.

---

## Graceful shutdown & background workers

When a container is recreated, Wokku sends the process a **`SIGTERM`**, waits for the **stop timeout (default 30s)**, then sends **`SIGKILL`**.

- **Web processes** usually handle this fine — finish in-flight requests, then exit.
- **Background workers** need care. A job still running when the 30s timeout elapses is **hard-killed**. Whether that's safe depends on your queue:
  - Sidekiq / Solid Queue re-enqueue jobs that were interrupted by `SIGTERM` *if they finish shutting down in time*.
  - A long job that runs past the stop timeout gets `SIGKILL`'d mid-execution. **Make jobs idempotent and transactional** so a re-run is safe, and checkpoint long work.

:::callout warn
Restarting an app restarts **all** its process types, not just `web`. So resizing your `web` box also bounces `worker` and `clock` processes — and any job they're running gets the SIGTERM → SIGKILL treatment. Plan resizes for low-traffic windows if you run long background jobs.
:::

---

## Resizing & restarts safely

Changing a box size doesn't edit a running container — it **recreates** it with the new memory/CPU limits (the kernel enforces them via cgroups). A few consequences:

- **Scaling up** (e.g. Medium → Large) is safe: more headroom, brief recreate, no data risk.
- **Scaling down** is the risky direction. If the app is currently using more memory than the new box allows, the new container can be **OOM-killed on boot** and crash-loop. Check your usage in [Monitoring](/docs/monitoring/health-checks) before downsizing.
- **Do it ahead of a spike.** The recreate causes a momentary capacity dip, so resize *before* traffic peaks, not in the middle of them.
- **A health check makes resizes graceful** (see above). Without one, expect a short blip on every resize.

See [Box Tiers](/docs/scaling/tiers) for sizes and [Restart / Stop / Start](/docs/apps/lifecycle) for the lifecycle commands.

---

## Pre-production checklist

- [ ] App runs on a **paid (always-on) box**, not Sleeping
- [ ] A **health check** is configured against a cheap, dependency-aware endpoint (e.g. `/up`)
- [ ] `CHECKS_WAIT` / `CHECKS_ATTEMPTS` are tuned for the app's real boot time
- [ ] No important data is written to the **container's local filesystem** — state lives in an addon or a mounted volume
- [ ] Background jobs are **idempotent** and tolerate `SIGTERM` mid-run
- [ ] You've confirmed current memory usage is **below** the box size before any downsize
- [ ] Resizes and restarts are scheduled for **low-traffic windows** when long jobs are running

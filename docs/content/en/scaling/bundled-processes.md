---
title: Bundling Processes
summary: "Run web + worker + scheduler in one container and use only one box. Same plan price, more headroom."
eyebrow: scaling
last_updated: 2026-05-29
---

# Bundling Processes in One Container

Save a box by running multiple processes inside a single Dokku container.

## When this matters

Wokku bills by **container boxs**: 1 Dokku container = 1 box, regardless of how many processes run inside it. The default Procfile pattern spawns one container per process type:

```
web: bundle exec rails server
worker: bundle exec sidekiq
```

That's two containers, **two boxs used.** On Pro (3 small + 2 medium) you'd burn 2-of-5 boxs before scaling at all.

For small apps where a process crash isn't critical, you can **bundle** the processes into one container and use **one box total**. Same plan price, more headroom.

## The pattern

Use a process manager (`foreman`, `honcho`, `supervisor`, `s6-overlay`) inside the container.

### Rails + Sidekiq example

`Gemfile`:
```ruby
gem "foreman"
gem "sidekiq"
```

`Procfile` (what Dokku reads):
```
web: foreman start -f Procfile.bundled
```

`Procfile.bundled` (what foreman reads):
```
rails: bundle exec rails server -p $PORT
sidekiq: bundle exec sidekiq
```

Deploy. Dokku sees one process type (`web`), runs one container. Inside, foreman supervises Rails + Sidekiq side-by-side.

### Django + Celery example

```
web: honcho start -f Procfile.bundled
```

`Procfile.bundled`:
```
django: gunicorn myproject.wsgi --bind 0.0.0.0:$PORT
celery: celery -A myproject worker --loglevel=info
```

### Node + worker example

```
web: npx concurrently "npm:start" "npm:worker"
```

## When to bundle vs split

| | Bundled (1 container) | Split (N containers) |
|---|---|---|
| **Box cost** | 1 | N |
| **Process isolation** | ✗ — crash in one kills the container | ✓ — each restarts independently |
| **Scaling** | All-or-nothing — `ps:scale web=2` doubles every process | ✓ — `web=3 worker=1` independently |
| **Deploys** | All restart together | ✓ — rolling per process type |
| **Logs** | Interleaved (use prefixed loggers) | ✓ — clean per-process streams |
| **Memory** | Shared cap — size for sum of peaks + 20% | Each gets the full tier allowance |

### Use bundled when

- Small / hobby / side-project app
- Background worker that handles low traffic (Sidekiq on a mostly-cron workload)
- You can size the container for the combined RAM peak comfortably
- Crash-isolation isn't a hard requirement

### Use split when

- Production scale — uneven scaling matters (3× web, 1× worker)
- One process being slow or crashing shouldn't affect the other's SLO
- You want clean log streams per process
- The worker is memory-heavy (image processing, ML inference) and can spike independently

## Memory sizing for bundled

Pick the container tier where:

```
container_memory >= sum(per-process peak RSS) + 20% headroom
```

Rough Rails + Sidekiq sizing on small ↔ medium tiers:

| Workload | Recommended tier |
|---|---|
| Rails dev/staging + low-volume Sidekiq | **Small** (512 MB) |
| Production Rails (~50-200 req/s) + Sidekiq with light jobs | **Medium** (2 GB) |
| Heavy Sidekiq jobs (image processing, PDF generation) | Split — give Sidekiq its own box |

## Internal routing (if you need multiple HTTP servers)

If your bundled processes both speak HTTP (e.g. Rails on `$PORT` + a FastAPI sidecar on `5001`), add an internal nginx that routes by path:

`nginx.conf`:
```
server {
  listen $PORT;
  location /api/ { proxy_pass http://127.0.0.1:5001; }
  location /     { proxy_pass http://127.0.0.1:3000; }
}
```

Then `Procfile.bundled`:
```
nginx: nginx -g "daemon off;"
rails: bundle exec rails server -p 3000
api: uvicorn api.main:app --port 5001 --host 127.0.0.1
```

Dokku still sees one `web` container.

## Starter templates

- [Rails + Sidekiq bundled starter](/templates) — production Rails 8 with Sidekiq supervised by foreman in one container. Deploy directly with one click.

## See also

- [Process Types & Dynos](/docs/scaling/dynos) — the default split-process model
- [Dyno Tiers](/docs/scaling/tiers) — pick the right size for your bundled container

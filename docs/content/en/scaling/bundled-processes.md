---
title: Bundling Processes
summary: Run web and worker in one container, so you pay for one size instead of two.
last_updated: 2026-11-09
---

You'll run several processes inside one container with a process manager.

## Why bundle

Each process type in your `Procfile` runs in its own container, and each container is billed for its CPU and RAM. This runs two containers:

```
web: bundle exec rails server
worker: bundle exec sidekiq
```

Two Starter containers (0.25 vCPU, 512 MB each) cost Rp48.000/month. One container with 0.25 vCPU and 1 GB holds both processes for Rp42.000/month, because they share the CPU. You save more with each extra process.

## The pattern

Make `web` start a process manager (`foreman`, `honcho`, `concurrently`, `supervisor`) that starts everything else.

### Rails + Sidekiq

`Gemfile`:
```ruby
gem "foreman"
gem "sidekiq"
```

`Procfile` (what Wokku reads):
```
web: bundle exec foreman start -f Procfile.bundled
```

`Procfile.bundled` (what foreman reads):
```
rails: bundle exec rails server -p $PORT
sidekiq: bundle exec sidekiq
```

Wokku sees one process type (`web`) and runs one container. Foreman runs Rails and Sidekiq side by side inside it.

### Django + Celery

`Procfile`:
```
web: honcho start -f Procfile.bundled
```

`Procfile.bundled`:
```
django: gunicorn myproject.wsgi --bind 0.0.0.0:$PORT
celery: celery -A myproject worker --loglevel=info
```

### Node + worker

```
web: npx concurrently "npm:start" "npm:worker"
```

## Bundle or split?

| | Bundled (1 container) | Split (one per process) |
|---|---|---|
| **Cost** | One size | One size per process |
| **Crash isolation** | A crash restarts everything | Each restarts on its own |
| **Scaling** | `web=2` doubles every process | Scale each one separately |
| **Logs** | Interleaved | One stream per process |
| **Memory** | Shared | Each has its own |

Bundle for hobby, staging and low-traffic apps. Split when you need to scale web and workers separately, or when a worker is memory-heavy (image processing, PDFs, ML).

## Sizing a bundled container

Give the container enough RAM for every process at its peak, plus about 20%:

| Workload | Suggested preset |
|---|---|
| Staging Rails + light Sidekiq | Starter (512 MB) or Standard (1 GB) |
| Production Rails + Sidekiq with light jobs | Large (2 GB) |
| Heavy jobs (images, PDFs) | Split — give the worker its own container |

Change the size on **Runtime** → **Scaling**. See [Resources & Sizing](/docs/scaling/resources).

## See also

- [Scaling Processes](/docs/scaling/dynos)
- [Background workers](/docs/guides/background-workers)

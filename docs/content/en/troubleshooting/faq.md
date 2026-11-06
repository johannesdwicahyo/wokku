---
title: FAQ
summary: "Most-asked questions about Wokku, supported languages, backups, the open-source split, Heroku migration, and the free tier."
eyebrow: troubleshooting
last_updated: 2026-05-29
---

# FAQ

## What is Wokku built on?

Wokku is inspired by [Dokku](https://dokku.com) and Heroku-style workflows, but runs on its own runtime (the wokkud host agent, Docker Swarm, and Caddy).

## Is Wokku self-hosted or managed?

Wokku Cloud (this site, `wokku.cloud`) is fully **managed** — we run the hosts for you. If you want to self-host, use the open-source **Community Edition** at [github.com/johannesdwicahyo/wokku](https://github.com/johannesdwicahyo/wokku), which is the same Rails app you can run on your own VPS.

## What languages are supported?

Any language. Wokku detects and builds Node.js, Python, Ruby, Go, PHP, Java and more automatically, and supports Dockerfiles for full flexibility. See the [framework recipes gallery](/docs/templates/browse) for one-click starters.

## How do backups work?

Wokku backs up databases to S3-compatible storage (AWS S3, Cloudflare R2, Backblaze B2, DigitalOcean Spaces, Wasabi). Configure automatic daily backups or create on-demand snapshots from the database's Backups tab.

## What's the difference between CE and Cloud?

**Community Edition (CE)** is free, open-source (AGPL-3.0), and runs on your own infrastructure. CE ships the **web UI only** — REST API, CLI, MCP server, and mobile app are Cloud-only surfaces. CE releases monthly on the 1st of each month, tagged `vYYYY.MM`.

**Wokku Cloud** is the managed service at [wokku.cloud](https://wokku.cloud) — we operate the hosts, billing runs on monthly invoices, you get the [bundled addons](/docs/billing/plan-bundles) per plan, plus the full surface (API + CLI + MCP + mobile).

See [Open Source Edition](/docs/oss/overview) for the full surface comparison.

## Can I migrate from Heroku?

Yes. Wokku follows the same workflow — `git push` to deploy, `Procfile` for process types, env vars for config. Most Heroku apps work with minimal changes.

## Is there a free tier?

Yes. [Wokku Cloud](https://wokku.cloud) offers a free plan with one box (256 MB RAM) plus shared Postgres and shared Redis. Self-hosted CE is always free.

## How do I get support?

- **Community Edition** — [GitHub Issues](https://github.com/johannesdwicahyo/wokku/issues)
- **Wokku Cloud** — Email [support@wokku.cloud](mailto:support@wokku.cloud)

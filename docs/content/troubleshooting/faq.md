# FAQ

## What is Dokku?

[Dokku](https://dokku.com) is an open-source Platform-as-a-Service (PaaS) that runs on your own servers. Wokku provides a web UI, API, CLI, and mobile app on top of Dokku.

## Can I use my own server?

Yes. Any VPS or dedicated server with Dokku installed works. Connect it from **Servers → Add Server** in the dashboard.

## What languages are supported?

Any language. Dokku supports Heroku buildpacks (Node.js, Python, Ruby, Go, PHP, Java, and more) plus Dockerfiles for full flexibility.

## How do backups work?

Wokku backs up databases to S3-compatible storage (AWS S3, Cloudflare R2, MinIO, Backblaze B2, DigitalOcean Spaces, Wasabi). Configure automatic daily backups or create on-demand snapshots.

## What's the difference between CE and EE?

**Community Edition (CE)** is free, open-source (AGPL-3.0), and includes all core features. **Enterprise Edition (EE)** adds usage-based billing, dyno tiers, eco dynos, auto-placement, and the mobile app. CE is for self-hosting, EE powers [wokku.dev](https://wokku.dev).

## Can I migrate from Heroku?

Yes. Wokku follows the same workflow — `git push` to deploy, `Procfile` for process types, environment variables for config. Most Heroku apps work with minimal changes.

## Is there a free tier?

Yes. The managed cloud at [wokku.dev](https://wokku.dev) offers a free tier with 256 MB RAM. Self-hosted CE is always free.

## How do I get support?

- **CE:** [GitHub Issues](https://github.com/johannesdwicahyo/wokku/issues)
- **EE:** Email [support@wokku.dev](mailto:support@wokku.dev)

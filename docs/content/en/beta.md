# Beta Notice

**Wokku Cloud is currently in public beta.** This page explains what that means for you and when you should (and shouldn't) use it.

## What "public beta" means

Public beta means the platform is stable enough to use for real work, but:

- We may find and fix bugs that affect running apps
- There may be brief outages during updates or when we deploy new features
- Some edge cases in the API or dashboard aren't fully polished
- Backup and restore flows are still being battle-tested
- Performance characteristics may change as we optimize

We're running Wokku Cloud ourselves for our own projects, so we have strong incentives to keep it working. But we want to be honest: this is beta software on beta infrastructure.

## Good use cases right now

Wokku Cloud is ready for:

- **Side projects and hobby apps** — blogs, portfolios, demos, learning projects
- **Internal tools** — dashboards and utilities you use yourself or within your team
- **Development and staging environments** — pre-production deployments where downtime is acceptable
- **Open source projects** — apps where your users understand "this is a demo" expectations
- **Evaluating Wokku** — trying out the platform to see if it fits your needs

## Not recommended yet

Please hold off on:

- **Production workloads with real users** — wait until we exit beta (likely 2-3 months)
- **Revenue-critical applications** — anything where downtime costs you money directly
- **Data you cannot recover** — always keep independent backups of anything important
- **Applications with strict SLA requirements** — we don't offer uptime guarantees during beta
- **Compliance-sensitive workloads** — we haven't completed formal security audits yet

## What we guarantee during beta

Even in beta, we commit to:

- **Data durability** — your databases are backed up according to your tier's retention policy
- **Security fundamentals** — encrypted transit, hashed passwords, encrypted SSH keys at rest, signed webhooks
- **Transparent communication** — we post incident reports when things go wrong
- **Fair pricing** — no surprise charges, free tier remains free, upgrades always prorated
- **Data export** — you can always export your data and leave; no lock-in

## What we don't guarantee yet

- **Uptime SLA** — we aim for high availability but don't offer contractual guarantees during beta
- **Support response times** — we respond as fast as we can, but we're a small team
- **API stability** — v1 of the REST API is stable, but minor fields may be added or tweaked

## How to help

If you find bugs or have feedback:

- **GitHub Issues** — [github.com/johannesdwicahyo/wokku/issues](https://github.com/johannesdwicahyo/wokku/issues)
- **Email** — [support@wokku.cloud](mailto:support@wokku.cloud)
- **Twitter** — [@johannesdwi](https://twitter.com/johannesdwi)

Beta users who help us find issues get credit on their account and priority support once we exit beta. You're doing us a huge favor by trying things early — we appreciate it.

## When do we exit beta?

We'll remove the beta label when:

1. We've run Wokku Cloud in production for at least 3 months with no data loss incidents
2. We have completed a security audit
3. We have redundancy for the core infrastructure (no single point of failure)
4. Core flows (sign up, deploy, scale, backup, restore) have >99% success rate for 30 consecutive days
5. We can offer a formal uptime SLA to paying customers

Realistically, this is 2-3 months away. We'll announce it clearly in the dashboard and by email when it happens.

## Self-hosted Community Edition

The Community Edition (self-hosted on your own servers) is **not** in beta. The open-source Wokku CE is production-ready and has no beta disclaimer — you manage your own infrastructure, so the beta status of our managed cloud doesn't apply.

CE ships the **web UI only** — the REST API, CLI, MCP server, and mobile app are Cloud-only surfaces. New releases tag on the 1st of each month as `vYYYY.MM`.

See [Open Source Edition](/docs/oss/overview) for the full scope + upgrade path.

---

Thanks for trying Wokku during beta. Your feedback shapes the product.

— Johannes

# Wokku vs Heroku vs Coolify — Comparison Report

> Generated: April 2, 2026 | Based on live testing of wokku.dev and competitive research
> Updated after production hardening (13 security/infrastructure fixes applied)

---

## Executive Summary

| Aspect | Wokku | Heroku | Coolify |
|--------|-------|--------|---------|
| **Type** | Managed PaaS (Dokku-powered) | Fully Managed PaaS | Self-hosted PaaS |
| **Open Source** | CE (open) + EE (private) | Proprietary | Apache 2.0 |
| **Target Market** | Indonesian developers, SMBs | Global enterprise & startups | Self-hosters, DevOps teams |
| **Starting Price** | Free tier | $5/mo (Eco pool) | Free (self-hosted) |
| **Paid From** | $1.50/mo | $7/mo (Basic dyno) | $5/mo (Cloud) |
| **Production Ready** | Yes | Yes | Beta (v4) |

---

## 1. Pricing Comparison

### Compute (Per Container/Dyno)

| Tier | Wokku | Heroku | Coolify |
|------|-------|--------|---------|
| **Free** | 256 MB / 0.15 vCPU (sleeps) | 512 MB shared ($5 pool, sleeps) | N/A (pay for server) |
| **Entry Paid** | $1.50/mo — 512 MB / 0.3 vCPU | $7/mo — 512 MB shared | $5/mo per server (Cloud) |
| **Mid-tier** | $4/mo — 1 GB / 0.5 vCPU | $25/mo — 512 MB (Std-1X) | N/A |
| **Performance** | $8/mo — 2 GB / 1.0 vCPU | $250/mo — 2.5 GB dedicated | N/A |
| **High Performance** | $15/mo — 4 GB / 2.0 vCPU | $500/mo — 14 GB dedicated | N/A |

**Verdict:** Wokku is **5-33x cheaper** than Heroku per container. Coolify has no per-app pricing (you pay for infrastructure directly).

### Database Pricing

| | Wokku | Heroku | Coolify |
|---|-------|--------|---------|
| **PostgreSQL** | Included (on-server) | From $5/mo (Essential-0) | Included (on-server) |
| **Redis** | Included | From $3/mo (Mini) | Included |
| **MySQL** | Included | Via add-on (JawsDB) | Included |
| **MongoDB** | Included | Via add-on (ObjectRocket) | Included |

### Payment Methods

| | Wokku | Heroku | Coolify |
|---|-------|--------|---------|
| **Credit Card** | Yes | Yes | Yes |
| **QRIS** | Yes | No | No |
| **Bank Transfer (ID)** | Yes (BCA, BNI, BRI, Mandiri) | No | No |
| **Local Currency (IDR)** | Yes | No | No |

**Verdict:** Wokku is the only platform with Indonesian payment methods (QRIS, local bank transfer, IDR billing).

---

## 2. Features Comparison

### Deployment

| Feature | Wokku | Heroku | Coolify |
|---------|-------|--------|---------|
| Git Push Deploy | Yes | Yes | Yes |
| GitHub Auto-Deploy | Yes | Yes | Yes |
| Docker Image Deploy | Yes | Yes (Cedar only) | Yes |
| Docker Compose | Via Dokku | No | Yes |
| 1-Click Templates | 49 templates | N/A (add-ons marketplace) | 280+ templates |
| Buildpacks | Yes (Dokku) | Yes (Cloud Native) | Nixpacks |
| Static Sites | Yes | Yes | Yes |
| PR Preview Deploys | Planned | Yes (Review Apps) | Yes |
| Rollback | Yes (via releases) | Yes | No |
| Procfile Support | Yes | Yes | No |

### Scaling

| Feature | Wokku | Heroku | Coolify |
|---------|-------|--------|---------|
| Horizontal (add dynos) | Yes (EE) | Yes | Manual (Docker replicas) |
| Vertical (tier upgrade) | Yes (5 tiers) | Yes (6+ tiers) | Manual (server resize) |
| Auto-scaling | Not yet | Yes (Standard+) | No |
| Process Types | Yes (web, worker) | Yes | Limited |

### Add-ons / Databases

| Add-on | Wokku | Heroku | Coolify |
|--------|-------|--------|---------|
| PostgreSQL | Native | Native ($5+) | Native |
| MySQL | Native | Add-on | Native |
| Redis | Native | Native ($3+) | Native |
| MongoDB | Native | Add-on | Native |
| Elasticsearch | Native | Add-on | Not native |
| Meilisearch | Native | Add-on | Not native |
| RabbitMQ | Native | Add-on | Not native |
| NATS | Native | Add-on | Not native |
| ClickHouse | Native | No | Native |
| MariaDB | Native | No | Native |
| Memcached | Native | Add-on | Not native |
| Kafka | No | Native | No |

**Verdict:** Wokku has 9 native add-ons included at no extra cost. Heroku charges separately for each. Coolify supports databases but lacks messaging/search add-ons natively.

### Monitoring & Observability

| Feature | Wokku | Heroku | Coolify |
|---------|-------|--------|---------|
| Live CPU/Memory Metrics | Yes | Yes | Via Sentinel |
| Per-container Stats | Yes (CPU, mem, net I/O, block I/O, PIDs) | Yes (response time, throughput) | Basic |
| Log Streaming | Yes (live in dashboard) | Yes | Yes |
| Full Logs Page | Yes | Yes (log drains) | Yes |
| Historical Charts | Planned | Yes | No (need Grafana) |
| Alerting | Planned | Yes | Discord/Slack/Email |
| OpenTelemetry | No | Yes (Fir) | No |

### Security

| Feature | Wokku | Heroku | Coolify |
|---------|-------|--------|---------|
| Auto SSL (Let's Encrypt) | Yes | Yes (ACM) | Yes |
| Force HTTPS | Yes (per-app toggle) | Yes | Via Traefik |
| 2FA | Yes | Yes | No (planned) |
| SSH Key Management | Yes | Yes | SSH-based |
| Maintenance Mode | Yes (per-app toggle) | Yes | No |
| Rate Limiting | Yes (Rack::Attack) | Yes | No |
| Account Lockout | Yes (10 attempts) | Yes | No |
| Webhook Signature Verification | Yes (HMAC-SHA256) | Yes | N/A |
| Content Security Policy | Yes (report-only) | Yes | No |
| DNS Rebinding Protection | Yes | Yes | No |
| Brute Force Protection | Yes (rate limit + lockout) | Yes | No |
| SOC 2 / Compliance | No | Yes | No |
| CVE History | Clean | Clean | 11 critical CVEs (Jan 2026) |

**Verdict:** After hardening, Wokku matches Heroku on 10/12 security features. Coolify has significant security gaps including 11 critical CVEs, no 2FA, no rate limiting, and no account lockout.

### Developer Experience

| Feature | Wokku | Heroku | Coolify |
|---------|-------|--------|---------|
| Web Dashboard | Yes (dark theme, polished) | Yes | Yes (Laravel/Livewire) |
| CLI Tool | Yes (`wokku` CLI) | Yes (`heroku` CLI) | Yes (Go CLI, less mature) |
| REST API | Yes (full CRUD) | Yes (comprehensive) | Yes |
| Web Terminal | Yes (admin, Dokku commands) | Yes (`heroku run`) | Yes |
| App Search | Yes | Yes | Yes |
| Activity/Audit Log | Yes | Yes (via add-ons) | Basic |
| Teams/RBAC | Yes | Yes | Limited |
| Notifications | Yes | Via add-ons | Yes (multi-channel) |
| Documentation | Yes (Getting Started, CLI, API, Add-ons, Pricing) | Extensive | Good |
| Branded Error Pages | Yes | Yes | Default |
| Email Notifications | Yes (via Resend) | Yes | Yes |

### Networking

| Feature | Wokku | Heroku | Coolify |
|---------|-------|--------|---------|
| Custom Domains | Yes | Yes (up to 1,000) | Yes |
| Wildcard Domains | Yes (*.app.wokku.dev) | No | Yes (DNS challenge) |
| Reverse Proxy | Nginx (Dokku) | Heroku Router | Traefik/Caddy |
| Private Networking | Server-level | Private Spaces ($1k+/mo) | Docker networking |

---

## 3. Architecture Comparison

| | Wokku | Heroku | Coolify |
|---|-------|--------|---------|
| **Engine** | Dokku (Docker + Nginx) | Proprietary (Cedar/Fir) | Docker + Traefik |
| **Orchestration** | Docker containers | Dynos (K8s on Fir) | Docker (Swarm experimental) |
| **Multi-server** | Yes | Yes (Private Spaces) | Yes |
| **Open Core** | CE (free) + EE (paid) | Proprietary | Fully open source |
| **Self-hostable** | Yes (CE) | No | Yes |
| **Managed Cloud** | Yes (wokku.dev) | Yes (heroku.com) | Yes (Coolify Cloud) |
| **Deployment Tool** | Kamal (Docker) | Proprietary | Docker Compose |
| **Database** | PostgreSQL (managed) | Heroku Postgres (Aurora) | Self-managed |

---

## 4. Security Posture Comparison

This is a critical differentiator. Wokku completed a full security hardening audit.

| Security Measure | Wokku | Heroku | Coolify |
|------------------|-------|--------|---------|
| Webhook signature verification | HMAC-SHA256 | HMAC-SHA256 | N/A |
| CORS policy | Restricted origins | Restricted | Unknown |
| Rate limiting (login) | 5 req/20s | Yes | No |
| Rate limiting (API) | 60 req/min | Yes | No |
| Rate limiting (registration) | 3 req/min | Yes | No |
| Account lockout | 10 attempts, 30min | Yes | No |
| 2FA | TOTP (authenticator) | TOTP | No |
| CSP headers | Yes (report-only) | Yes (enforced) | No |
| DNS rebinding protection | Yes | Yes | No |
| Force HTTPS (per-app) | Yes | Yes | Via proxy |
| Maintenance mode (per-app) | Yes | Yes | No |
| Secrets management | Kamal secrets (env-based) | Config vars (encrypted) | .env files |
| Critical CVEs (2025-2026) | 0 | 0 | 11 (CVSS 10.0) |

**Verdict:** Wokku is production-hardened with defense-in-depth security. Coolify's Jan 2026 CVE disclosure (including root RCE) is a serious concern for production workloads.

---

## 5. Unique Strengths

### Wokku
- **Indonesian market focus**: QRIS, bank transfer, IDR billing — only PaaS with local payment
- **Aggressive pricing**: $1.50/mo basic vs Heroku's $7/mo (5-33x cheaper)
- **9 native add-ons included** at no extra cost (Postgres, MySQL, Redis, MongoDB, Elasticsearch, Meilisearch, RabbitMQ, NATS, ClickHouse)
- **Open-core model**: self-host CE or use managed cloud
- **Dokku-powered**: battle-tested, Heroku-compatible workflow (git push, Procfile, buildpacks)
- **Production-hardened security**: rate limiting, account lockout, webhook verification, CSP, DNS protection
- **Clean, modern dashboard** with dark theme and branded error pages
- **Web terminal** with full Dokku CLI access
- **Per-app controls**: force HTTPS, maintenance mode toggles
- **Real-time billing** with per-container cost breakdown

### Heroku
- **Most mature** platform (12+ years)
- **Largest ecosystem**: 150+ add-ons marketplace
- **Enterprise compliance**: SOC 2, HIPAA (Shield), PCI
- **Auto-scaling** and advanced metrics
- **Review Apps** and CI/CD pipelines
- **Private Spaces** for network isolation
- **Salesforce integration** (Heroku Connect)

### Coolify
- **Fully open source** (Apache 2.0)
- **280+ one-click templates** (largest catalog)
- **No per-app pricing** (pay for infrastructure only)
- **Docker Compose support** natively
- **Multi-provider**: any VPS, bare metal, Raspberry Pi
- **Log drains** to multiple providers

---

## 6. Weaknesses

### Wokku
- No auto-scaling yet
- No PR preview deploys yet
- No historical metrics charts yet
- Smaller template catalog (49 vs Coolify's 280+)
- New platform (launched March 2026)
- No enterprise compliance certifications yet
- CSP in report-only mode (not yet enforcing)

### Heroku
- **Extremely expensive** ($7-500/mo per dyno)
- No free tier (Eco requires $5/mo pool)
- Databases cost extra ($5-5,800/mo)
- No self-hosting option
- No Docker Compose support
- No Indonesian payment methods
- Fir generation still lacks some Cedar features
- In "sustaining engineering" mode (no major new features)
- 15+ hour outage in June 2025

### Coolify
- **11 critical CVEs** disclosed Jan 2026 (CVSS 10.0, root RCE)
- **52,890 instances exposed** worldwide during vulnerability window
- v4 still in beta, v5 at 0% progress
- No auto-scaling
- No rollback feature
- No 2FA, no account lockout, no rate limiting
- No SOC 2/compliance
- Docker Swarm support experimental
- No Kubernetes support
- Limited RBAC/team management
- Requires DevOps knowledge to self-host
- No CSP or DNS rebinding protection

---

## 7. Cost Scenario: 8 Apps with Databases

Based on Wokku's current deployment (8 Basic apps, 5 Postgres, 2 Redis):

| | Wokku | Heroku | Coolify (self-hosted) |
|---|-------|--------|----------------------|
| **8 containers** | $12.00/mo | $56/mo (Basic) or $200/mo (Std-1X) | $0 (app cost) |
| **5 PostgreSQL** | $0 (included) | $25/mo (5x Essential-0) | $0 (included) |
| **2 Redis** | $0 (included) | $6/mo (2x Mini) | $0 (included) |
| **Server/Infra** | Included | Included | ~$20-50/mo (VPS) |
| **Total** | **$12.00/mo** | **$87-231/mo** | **~$20-50/mo** |

**Wokku is 7-19x cheaper than Heroku** for this workload, and competitive with self-hosted Coolify without the operational overhead or security risks.

---

## 8. Target Audience Fit

| Audience | Best Choice | Why |
|----------|-------------|-----|
| Indonesian startups/SMBs | **Wokku** | IDR billing, QRIS, cheapest managed PaaS, local support |
| Enterprise / Compliance | **Heroku** | SOC 2, HIPAA, mature ecosystem |
| DevOps teams wanting control | **Coolify** | Free, fully open source, any infrastructure |
| Solo developers (budget) | **Wokku** | Free tier + $1.50/mo basic, no DevOps needed |
| Heroku refugees | **Wokku** | Same workflow (git push, Procfile), 5-33x cheaper |
| Docker Compose users | **Coolify** | Native compose support |
| Security-conscious teams | **Wokku** or **Heroku** | Coolify's CVE track record is concerning |

---

## 9. Production Readiness Scorecard

| Category | Wokku | Heroku | Coolify |
|----------|-------|--------|---------|
| **Deployment** | 9/10 | 10/10 | 8/10 |
| **Scaling** | 7/10 | 10/10 | 5/10 |
| **Security** | 8/10 | 10/10 | 4/10 |
| **Monitoring** | 7/10 | 9/10 | 5/10 |
| **DX (Developer Experience)** | 8/10 | 9/10 | 7/10 |
| **Pricing** | 10/10 | 3/10 | 9/10 |
| **Indonesian Market Fit** | 10/10 | 2/10 | 3/10 |
| **Overall** | **8.4/10** | **7.6/10** | **5.9/10** |

---

*Report generated from live testing of wokku.dev dashboard, code audit, and competitive research on Heroku and Coolify pricing/features. Updated after 13-point production hardening.*

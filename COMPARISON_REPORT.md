# Wokku vs The PaaS Landscape — Competitive Analysis

> Generated: April 2, 2026 | Live-tested on wokku.dev (post-production hardening)
> Competitors: Heroku, Coolify, Railway, Render, Fly.io, DigitalOcean App Platform

---

## Executive Summary

| Platform | Type | Starting Price | Free Tier | IDR/Local Pay | Production Ready |
|----------|------|---------------|-----------|---------------|-----------------|
| **Wokku** | Managed PaaS (Dokku) | $1.50/mo | Yes | Yes (QRIS, Bank, IDR) | Yes |
| **Heroku** | Managed PaaS | $5/mo (Eco) | No | No | Yes (sustaining mode) |
| **Coolify** | Self-hosted PaaS | $0 (self-host) | Yes | No | Beta (v4) |
| **Railway** | Managed PaaS | $5/mo | Trial only | No | Yes |
| **Render** | Managed PaaS | $7/mo | Yes (static) | No | Yes |
| **Fly.io** | Edge PaaS | ~$4/mo | Trial only | No | Yes |
| **DO App Platform** | Managed PaaS | $5/mo | Yes (static) | No | Yes |

**Wokku is the only PaaS with Indonesian payment methods and IDR billing.**

---

## 1. Pricing Comparison

### Cheapest Always-On App (512 MB RAM)

| Platform | Monthly Cost | Notes |
|----------|-------------|-------|
| **Wokku** | **$1.50** | Basic tier, 512 MB, 0.3 vCPU |
| Fly.io | ~$4.00 | Shared-CPU 256 MB + $2 IPv4 |
| Heroku | $7.00 | Basic Dyno, shared CPU |
| Render | $7.00 | Starter, 512 MB |
| Railway | $5.00+ | $5 sub + usage-based (unpredictable) |
| DO App Platform | $5.00 | Fixed Shared, limited specs |
| Coolify | $0 + VPS | Self-hosted (VPS ~$5-20/mo) |

### App + Database (PostgreSQL)

| Platform | App + Postgres | Total |
|----------|---------------|-------|
| **Wokku** | $1.50 + $0 | **$1.50/mo** |
| Heroku | $7 + $5 | $12/mo |
| Render | $7 + $7 | $14/mo |
| Railway | $5 + usage | ~$10-15/mo |
| DO App Platform | $5 + $7 | $12/mo |
| Fly.io | ~$4 + $2 (volume) | ~$6/mo |
| Coolify | $0 + VPS | ~$5-20/mo |

### 8 Apps + 5 Postgres + 2 Redis (Wokku's Current Setup)

| Platform | Compute | Databases | Total |
|----------|---------|-----------|-------|
| **Wokku** | $12.00 | $0 (included) | **$12.00/mo** |
| Coolify (self-hosted) | $0 | $0 | ~$20-50/mo (VPS) |
| Railway | $40+ | $20+ | ~$60-80/mo |
| Render | $56 | $49 | ~$105/mo |
| Heroku (Basic) | $56 | $31 | **$87/mo** |
| Heroku (Std-1X) | $200 | $31 | **$231/mo** |
| DO App Platform | $40 | $56 | ~$96/mo |
| Fly.io | ~$32 | ~$16 | ~$48/mo |

**Wokku is 4-19x cheaper than managed alternatives for real workloads.**

### Payment Methods

| | Wokku | Heroku | Railway | Render | Fly.io | DO | Coolify |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Credit Card | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| **QRIS** | **Yes** | - | - | - | - | - | - |
| **Bank Transfer (ID)** | **Yes** | - | - | - | - | - | - |
| **IDR Billing** | **Yes** | - | - | - | - | - | - |

---

## 2. Features Comparison

### Deployment

| Feature | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Git Push Deploy | Yes | Yes | Yes | Yes | CLI | Yes | Yes |
| GitHub Auto-Deploy | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Docker Deploy | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Docker Compose | Dokku | - | - | - | - | - | Yes |
| 1-Click Templates | 49 | - | 50+ | - | - | - | 280+ |
| Buildpacks | Yes | Yes | Nixpacks | Yes | - | Yes | Nixpacks |
| PR Previews | Planned | Yes | Yes | Yes | - | Yes | Yes |
| Rollback | Yes | Yes | Yes | Yes | Yes | Yes | - |
| Procfile | Yes | Yes | Yes | Yes | - | Yes | - |
| Static Sites | Yes | Yes | Yes | Yes | Yes | Yes | Yes |

### Scaling

| Feature | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Horizontal | Yes (EE) | Yes | Yes | Yes | Yes | Yes | Manual |
| Vertical (tiers) | 5 tiers | 6+ tiers | Flexible | 7 tiers | Flexible | 6 tiers | Manual |
| Auto-scaling | - | Yes | - | Yes | Yes | Yes | - |
| Scale-to-zero | Sleep (free) | Sleep (Eco) | - | Sleep (free) | Yes | Yes | - |
| Process Types | Yes | Yes | Yes | Yes | Yes | Yes | Limited |

### Native Add-ons (Included, No Extra Cost)

| Add-on | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|--------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | Yes | $5+ | Usage | $7+ | $2+ | $7+ | Yes |
| MySQL | Yes | Add-on | Usage | - | $2+ | $7+ | Yes |
| Redis | Yes | $3+ | Usage | $10+ | - | $8+ | Yes |
| MongoDB | Yes | Add-on | Usage | - | - | $15+ | Yes |
| Elasticsearch | Yes | Add-on | - | - | - | - | - |
| Meilisearch | Yes | - | - | - | - | - | - |
| RabbitMQ | Yes | Add-on | - | - | - | - | - |
| NATS | Yes | - | - | - | - | - | - |
| ClickHouse | Yes | - | - | - | - | - | Yes |
| MariaDB | Yes | - | - | - | - | - | Yes |
| Memcached | Yes | Add-on | - | - | - | - | - |

**Wokku: 11 native add-ons included free. Next closest: Coolify (6), Railway (3).**

### Monitoring & Observability

| Feature | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Live Metrics | Yes | Yes | Yes | Yes | Yes | Yes | Sentinel |
| Per-container Stats | Yes | Yes | Yes | Basic | Yes | Basic | Basic |
| Log Streaming | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Historical Charts | Planned | Yes | Yes | Yes | Yes | Yes | - |
| Alerting | Planned | Yes | - | Yes | Yes | Yes | Multi-ch |

---

## 3. Security Comparison

This is where Wokku differentiates strongly from most competitors after production hardening.

| Security Feature | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|-----------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Auto SSL | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Force HTTPS | Per-app | Yes | Yes | Yes | Yes | Yes | Proxy |
| 2FA | Yes | Yes | Yes | Yes | Yes | Yes | - |
| Rate Limiting | Yes | Yes | ? | ? | ? | ? | - |
| Account Lockout | Yes | Yes | ? | ? | ? | ? | - |
| Webhook Signing | HMAC-256 | HMAC-256 | N/A | N/A | N/A | N/A | N/A |
| CSP Headers | Yes | Yes | ? | ? | ? | ? | - |
| DNS Rebinding Protection | Yes | Yes | ? | ? | ? | ? | - |
| Maintenance Mode | Per-app | Yes | - | - | - | - | - |
| SOC 2 | - | Yes | Yes | Yes | - | Yes | - |
| Critical CVEs (2025-26) | **0** | **0** | **0** | **0** | **0** | **0** | **11** |

**Coolify had 11 critical CVEs (CVSS 10.0) in Jan 2026 including root RCE, affecting ~53,000 instances.**

---

## 4. Developer Experience

| Feature | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Web Dashboard | Dark theme | Yes | Modern | Clean | Minimal | Yes | Livewire |
| CLI Tool | `wokku` | `heroku` | `railway` | - | `flyctl` | `doctl` | Go CLI |
| REST API | Full CRUD | Full | Full | Full | Full | Full | Yes |
| Web Terminal | Yes | `heroku run` | - | Shell | `fly ssh` | Console | Yes |
| Activity Log | Yes | Add-ons | Yes | Yes | - | Yes | Basic |
| Teams/RBAC | Yes | Yes | Yes | Yes | Yes | Yes | Limited |
| Documentation | Good | Extensive | Good | Good | Good | Good | Good |
| Branded Errors | Yes | Yes | Yes | Yes | - | Yes | Default |

---

## 5. Architecture

| | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|---|---|---|---|---|---|---|---|
| **Engine** | Dokku | Proprietary | K8s-based | Proprietary | Firecracker | K8s | Docker |
| **Deploy Tool** | Kamal | Git push | Git push | Git push | `flyctl` | Git push | Git push |
| **Open Source** | CE (open) + EE | No | No | No | Partial | No | Full |
| **Self-hostable** | Yes (CE) | No | No | No | No | No | Yes |
| **Multi-region** | Manual | Private Spaces | US/EU | 3 regions | 35+ regions | 8 regions | Any VPS |
| **Nearest to ID** | Custom VPS | US/EU | US | Singapore | Singapore | Singapore | Any |

---

## 6. Platform Health & Trajectory (April 2026)

| Platform | Status | Risk Assessment |
|----------|--------|----------------|
| **Wokku** | New, actively developed, production-hardened | Low risk — indie, growing |
| **Heroku** | Sustaining engineering mode (Feb 2026). No new features. | **High risk** — managed decline under Salesforce |
| **Coolify** | v4 still in beta, v5 at 0%, 11 critical CVEs in Jan 2026 | **Medium risk** — single maintainer, security concerns |
| **Railway** | Active development, growing user base | Low risk |
| **Render** | Stable, VC-funded, expanding | Low risk |
| **Fly.io** | Active but complex pricing changes, some reliability concerns | Low-medium risk |
| **DO App Platform** | Stable, backed by DigitalOcean | Low risk |

---

## 7. Unique Strengths Per Platform

### Wokku
- Only PaaS with **QRIS, Indonesian bank transfer, IDR billing**
- **5-33x cheaper** than Heroku, cheapest managed PaaS overall
- **11 native add-ons included free** (most in the industry)
- **Open-core**: self-host CE or use managed cloud
- **Heroku-compatible** workflow (git push, Procfile, buildpacks)
- **Production-hardened** security (rate limiting, lockout, CSP, webhook signing)
- Real-time billing with per-container cost breakdown

### Heroku
- Most mature (12+ years), largest add-on ecosystem (150+)
- Enterprise compliance (SOC 2, HIPAA, PCI)
- *But*: sustaining engineering mode, no new features, expensive

### Coolify
- Fully open source, 280+ templates, free forever
- *But*: 11 critical CVEs, still in beta, single maintainer

### Railway
- Best developer experience, instant deploys, clean UI
- *But*: usage-based pricing can surprise, no free tier

### Render
- Heroku simplicity with free tier, predictable pricing
- *But*: limited regions, sleep on free tier, fewer add-ons

### Fly.io
- 35+ global regions, edge deployment, Firecracker VMs
- *But*: complex pricing, CLI-only, steep learning curve

### DO App Platform
- Part of DigitalOcean ecosystem, 99.95% SLA
- *But*: fewer PaaS features, limited buildpacks

---

## 8. Target Audience Fit

| Audience | Best Choice | Runner-up | Why |
|----------|-------------|-----------|-----|
| Indonesian startups/SMBs | **Wokku** | DO App Platform | Only one with IDR/QRIS, cheapest |
| Solo developer (budget) | **Wokku** | Render | $1.50/mo with free DB vs $14/mo |
| Heroku refugees | **Wokku** | Railway | Same workflow, 5-33x cheaper |
| Global edge apps | **Fly.io** | Railway | 35+ regions, Firecracker VMs |
| Enterprise/compliance | **Heroku** | Render | SOC 2, HIPAA (while it lasts) |
| Self-hosters/DevOps | **Coolify** | Wokku CE | Free, but watch CVE track record |
| Docker Compose users | **Coolify** | Wokku (Dokku) | Native compose support |
| Best DX | **Railway** | Render | Instant deploys, clean UI |

---

## 9. Production Readiness Scorecard

| Category | Wokku | Heroku | Railway | Render | Fly.io | DO App | Coolify |
|----------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Deployment | 9 | 10 | 9 | 9 | 8 | 8 | 8 |
| Scaling | 7 | 9 | 8 | 8 | 10 | 8 | 5 |
| Security | 8 | 10 | 8 | 8 | 7 | 8 | 4 |
| Monitoring | 7 | 9 | 8 | 8 | 7 | 7 | 5 |
| DX | 8 | 8 | 9 | 8 | 6 | 7 | 7 |
| Pricing | **10** | 3 | 6 | 6 | 7 | 6 | 9 |
| Indonesian Fit | **10** | 2 | 2 | 2 | 3 | 3 | 3 |
| **Overall** | **8.4** | 7.3 | 7.1 | 7.0 | 6.9 | 6.7 | 5.9 |

---

*Report based on live testing of wokku.dev (post-hardening deploy), competitive research, and current pricing pages as of April 2, 2026.*

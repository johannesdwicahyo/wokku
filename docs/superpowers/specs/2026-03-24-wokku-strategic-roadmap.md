# Wokku Strategic Roadmap

## Market Position

Wokku occupies a unique position that no competitor currently holds:

**"The only open-source PaaS that is BOTH a self-hosted Coolify alternative AND a managed PetaPod/PikaPods-like cloud service."**

| Competitor | Self-Hosted | Managed Cloud | Open-Core | Dokku-Based | Indonesian Market |
|---|---|---|---|---|---|
| Coolify | Yes (free) | Yes ($5/mo) | No (Apache) | No | No |
| Dokploy | Yes (free) | Yes ($4.50/mo) | No (Apache) | No | No |
| PetaPod | No | Yes | No | Unknown | Yes |
| SumoPod | No | Yes | No | No | Yes |
| PikaPods | No | Yes | No | No | No |
| Elestio | No | Yes ($14/mo) | No | No | No |
| Easypanel | Yes (free) | No | Yes (freemium) | No | No |
| **Wokku** | **Yes (AGPL)** | **Yes (wokku.dev)** | **Yes** | **Yes** | **Yes** |

---

## Competitive Analysis Summary

### Coolify (our open-source benchmark)
- **52K GitHub stars**, 351 templates, 412 contributors
- **Strengths:** Massive community, Docker Compose support, Nixpacks auto-detection, 6 notification channels, Hetzner integration, comprehensive API
- **Weaknesses:** Still in beta (5 years!), primitive monitoring (no CPU/RAM graphs), basic RBAC (3 roles only), no Kubernetes, high CPU usage bugs, PHP/Laravel stack
- **Template format:** YAML-based Docker Compose with metadata comments

### PetaPod (our commercial benchmark)
- **30+ apps**, Indonesian + Chinese markets
- **Features:** 1-click deploy, terminal, monitoring, file manager, custom domains, 2FA
- **Weaknesses:** No pricing transparency, no public reviews, small market presence

### PikaPods (global managed benchmark)
- **60-80+ apps**, from $1.20/mo, Swiss privacy focus
- **Differentiator:** OSS revenue sharing (10-15% to app authors)

### Dokploy (fastest growing self-hosted)
- **26K stars**, 200+ templates, lightest footprint (350MB idle)
- **Differentiator:** Native Docker Compose, fastest dev pace

---

## Strategic Priorities

### OPEN SOURCE SIDE: Match Coolify's Feature Set

**Current Wokku vs Coolify gap:**

| Feature | Coolify | Wokku | Priority | Effort |
|---|---|---|---|---|
| Templates | 351 (Docker Compose YAML) | 51 (JSON) | High | Medium |
| Build systems | Nixpacks, Dockerfile, Compose, Static | Dokku buildpacks + Dockerfile | Medium | Large |
| GitHub/GitLab App integration | Full OAuth + webhooks | Git push only | **Critical** | Large |
| PR preview deployments | Yes | No | High | Medium |
| Docker Compose support | Native | No | **Critical** | Large |
| Web terminal (xterm.js) | Yes | No | **Critical** | Medium |
| Database backups to S3 | Yes (8 DB types) | No | **Critical** | Medium |
| Notifications (6 channels) | Discord, Telegram, Slack, Email, Pushover, Webhook | Email only | High | Small |
| Proxy options | Traefik, Nginx, Caddy | Nginx (Dokku default) | Low | N/A |
| Hetzner server provisioning | Yes (API) | No | Medium | Medium |
| Activity/audit log | Yes (spatie) | No | Medium | Small |
| Scheduled tasks (cron) | Yes | No | Medium | Medium |
| Cloudflare Tunnels | Yes | No | Low | Small |
| OAuth providers (8) | GitHub, Google, Discord, Azure, etc. | Devise (email/password) | Medium | Medium |
| API documentation (Swagger) | Yes | No | Medium | Small |
| File manager | No (in dev) | No | Low | Medium |

**What Wokku does better than Coolify:**
- Built on Dokku (proven, stable, 10+ years)
- Not in beta — Dokku is production-grade
- CLI tool (Coolify's CLI is minimal)
- Usage-based billing system (Coolify has none)
- MCP server for AI agents
- Lighter stack (Ruby vs PHP)

### COMMERCIAL SIDE: Match/Exceed PetaPod UX

**Current Wokku Cloud vs PetaPod gap:**

| Feature | PetaPod | Wokku Cloud | Priority | Effort |
|---|---|---|---|---|
| App catalog | 30+ | 51 | Done (ahead) | - |
| 1-click deploy | Yes | Yes | Done | - |
| Custom domains | Yes | Yes (manual) | Need auto-setup | Small |
| Terminal access | Yes | No | **Critical** | Medium |
| File manager | Yes | No | Medium | Medium |
| Real-time monitoring | Yes | Partial | High | Medium |
| Deployment logs (real-time) | Yes | No (static) | **Critical** | Medium |
| Auto-updates | Yes | No | Medium | Medium |
| IDR pricing | No (but Indonesian) | No | High | Small |
| Free trial | Yes (1 month) | Yes (free tier) | Done | - |
| Referral/affiliate program | Yes | No | Low | Medium |
| Multilingual (ID/EN/ZH) | Yes | EN only | Medium | Medium |

---

## Phased Roadmap

### Phase 1: Critical Gaps (4-6 weeks)
*Goal: Achieve feature parity on the features users compare first*

1. **Web Terminal** — xterm.js in dashboard, SSH to Dokku server
   - Both audiences need this (devs for debugging, non-tech for management)
   - Use ActionCable + xterm.js (same approach as Coolify)

2. **GitHub App Integration** — OAuth connect, repo browser, webhook auto-deploy
   - This is Coolify's killer feature for developers
   - Connect GitHub account → select repo → auto-deploy on push
   - Support GitHub, GitLab, Bitbucket

3. **Real-time Deploy Logs** — Stream build output to dashboard via ActionCable
   - Currently deploys show no progress — users don't know what's happening
   - Critical for both audiences

4. **Database Backups to S3** — Scheduled + on-demand, S3-compatible storage
   - Data safety is #1 concern for paying users
   - Support: Postgres, MySQL, MariaDB, MongoDB, Redis

5. **Multi-channel Notifications** — Discord, Telegram, Slack, Webhook
   - Already have email (CE). Add 4 more channels.
   - Small effort, high visibility

### Phase 2: Competitive Parity (6-8 weeks)
*Goal: No reason to choose Coolify over Wokku*

6. **Docker Compose Support** — Deploy multi-container apps via docker-compose.yml
   - Many self-hosted apps (Supabase, Plausible, Immich) need this
   - Dokku has `dokku-compose` plugin or we implement our own

7. **Template Format Upgrade** — Switch from JSON to Docker Compose YAML (like Coolify)
   - Easier for community to contribute
   - Compatible with existing Docker Compose files
   - Increase catalog from 51 to 200+ (import from Coolify/Dokploy)

8. **PR Preview Deployments** — Auto-deploy PRs to temporary URLs
   - GitHub webhook → create temp app → deploy → comment URL on PR

9. **Activity/Audit Log** — Track all actions (who deployed what, when)
   - Important for teams and enterprise users

10. **OAuth Sign-in** — GitHub, Google login
    - Reduces friction for signups (especially developers)

11. **Swagger API Docs** — Auto-generated API documentation
    - Developers expect this

### Phase 3: Differentiation (8-12 weeks)
*Goal: Features that make Wokku uniquely better*

12. **Server Provisioning** — Create servers directly from Wokku (Hetzner, Vultr, DO API)
    - Like Coolify's Hetzner integration but multi-provider
    - "Add Server" → pick provider → pick region → server created and configured

13. **IDR Pricing + Multi-currency** — For Indonesian market
    - Rupiah billing for local users
    - Stripe supports IDR

14. **Bahasa Indonesia / Multilingual** — i18n support
    - PetaPod serves ID/EN/ZH — we should at least match ID/EN

15. **OSS Revenue Sharing** — Like PikaPods (10-15% to app authors)
    - Major differentiator, builds goodwill with open source community

16. **Mobile App (EE)** — Already planned in milestones
    - Neither Coolify nor PetaPod has this

17. **AI-Assisted Deployment** — Use MCP server + LLM to help debug failed deploys
    - Unique feature no competitor has
    - "Deploy failed? Ask AI to diagnose"

### Phase 4: Scale (ongoing)
18. **400+ Templates** — Match Elestio's catalog
19. **Kubernetes Support** — For enterprise users
20. **Multi-tenancy** — White-label Wokku for hosting providers
21. **Marketplace** — Let third parties publish templates (like app stores)

---

## Architecture Decisions

### Template Format: Migrate from JSON to Docker Compose YAML

**Current (Wokku):**
```json
{
  "name": "n8n",
  "deploy_method": "docker_image",
  "docker_image": "n8nio/n8n",
  "addons": [{"type": "postgres"}]
}
```

**Proposed (Coolify-compatible):**
```yaml
# documentation: https://n8n.io
# slogan: Workflow automation tool
# category: automation
# tags: automation, workflow, node
# logo: svgs/n8n.svg
# port: 5678

services:
  n8n:
    image: n8nio/n8n:latest
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${POSTGRES_HOST}
    depends_on:
      - postgres
  postgres:
    image: postgres:16
    environment:
      - POSTGRES_PASSWORD=${SERVICE_PASSWORD_POSTGRES}
    volumes:
      - pg-data:/var/lib/postgresql/data
volumes:
  pg-data:
```

**Benefits:**
- Community can contribute templates by copying existing Docker Compose files
- Compatible with Coolify's 351 templates (easy to import)
- Standard format — no proprietary JSON schema to learn
- Multi-container apps work naturally

### Web Terminal: xterm.js + ActionCable

```
Browser (xterm.js) → ActionCable WebSocket → Rails server
  → SSH to Dokku server → Execute command → Stream output back
```

### Git Integration: GitHub App (not just OAuth)

GitHub Apps are more powerful than OAuth tokens:
- Repository-level permissions (not full account access)
- Webhook auto-configuration
- Installation flow is familiar to developers
- Can list repos, branches, create deploy hooks

---

## Success Metrics

### Open Source (6-month targets)
- GitHub stars: 1,000+ (from 0 today)
- Templates: 200+
- Contributors: 10+
- Monthly active self-hosted instances: 100+

### Commercial (6-month targets)
- Registered users on wokku.dev: 500+
- Paying users: 50+
- Monthly revenue: $500+
- App deployments: 1,000+

---

## Execution Order

The most impactful work in priority order:

1. **Web Terminal** — biggest visible gap, both audiences need it
2. **Real-time Deploy Logs** — users need to see what's happening
3. **GitHub Integration** — developers won't use a PaaS without this
4. **Database Backups** — paying users need data safety
5. **Notifications (Discord/Telegram)** — quick win, high visibility
6. **Docker Compose Support** — unlocks complex apps
7. **Template Format Migration** — unlocks 300+ templates from Coolify
8. **PR Preview Deployments** — developer workflow differentiator
9. **OAuth Sign-in** — reduce signup friction
10. **Server Provisioning** — complete the "zero to deployed" story

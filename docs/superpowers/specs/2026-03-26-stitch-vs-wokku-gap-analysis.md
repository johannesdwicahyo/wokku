# Stitch Design vs Wokku Feature Gap Analysis

## Screen-by-Screen Comparison

### 1. Dashboard (Apps List)

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| App cards with name, status badge | Yes | - |
| Region tags (US-EAST-1, EU-WEST-1) | No | **Need server region on app cards** |
| Version number (V2.4.12-STABLE) | No | **Need release version on app cards** |
| Latency metric per app (150ms) | No | **Need response time metric per app** |
| Mini sparkline chart per app | No | **Need inline mini chart** |
| Filter tabs (All/Production/Staging) | No | **Need app environment filters** |
| "Personal & Teams" toggle | Partial (teams exist, no toggle) | **Need team switcher** |
| Compute Usage % stat | No | **Need aggregate server stats** |
| DB Health % stat | No | **Need database health aggregation** |
| Total Dynos count | No | **Need total process count** |
| Search icon in header | Yes (templates only) | **Need app search** |

### 2. App Detail

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| App name, status badge | Yes | - |
| Environment + region label | No | **Need environment/region metadata** |
| Version + "12 mins ago" | No | **Need last deploy time on detail** |
| "View Logs" button | Yes | - |
| "Open App" button | No | **Need "Open in browser" action** |
| Response Time (P95) metric card | No | **Need P95 response time metric** |
| Throughput (rpm) metric card | No | **Need throughput metric** |
| Error Rate metric card | No | **Need error rate metric** |
| Bento grid metric layout | No | **Need bento grid layout** |
| Recent Activity timeline | Partial (deploys only) | **Need broader activity (scale, config)** |
| Activity with user avatars | No | **Need user attribution on events** |
| Formation (web.1, worker.1) | No | **Need process formation display** |
| "Configure Dynos" action | Partial (scaling exists) | **Need inline dyno config** |
| Resources list (Postgres, Redis, SendGrid) | No | **Need linked resources on app detail** |

### 3. Resources

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| Dyno formation with process commands | No | **Need Procfile/process command display** |
| Scaling controls per process | Yes (separate page) | **Need inline scaling** |
| Hobby vs Professional tier display | Partial (tiers exist) | **Need tier comparison UI** |
| Add-on list with pricing | Partial (databases listed) | **Need add-on pricing display** |
| Add-on health/usage (Redis 28.4MB/100MB) | No | **Need add-on resource usage** |
| Cost projection summary | Partial (billing page) | **Need per-app cost projection** |

### 4. Improved Logs View

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| App status header (Running, dynos, region) | Partial | **Need dyno + region in log view** |
| Deployment history (v142, v141, v140) | Yes | - |
| Failed deploy indicator (v140 Failed) | Yes | - |
| Live log stream with timestamps | Yes (basic) | **Need severity-colored log lines** |
| Log severity levels (Info, Error, Debug) | No | **Need log level parsing + coloring** |
| "Live Connection" indicator | No | **Need WebSocket status indicator** |
| Deploy user attribution | Partial | **Need user avatars on deploys** |

### 5. Settings

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| User profile card with avatar | Yes | - |
| Verified badge + Plan badge | No | **Need verification + plan display** |
| Change Password | Yes (Devise) | - |
| Two-Factor Auth (SMS/TOTP) | No | **Need 2FA** |
| API token display (masked) | Partial (tokens exist) | **Need masked token display in settings** |
| Rotate Key action | No | **Need API key rotation** |
| Build Status Alerts toggle | Partial (notifications) | **Need per-type alert toggles** |
| Critical Log Alerts toggle | No | **Need error alert config** |
| Terminate Session | Yes (logout) | - |

### 6. Billing & Usage

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| Projected cost for current cycle | Yes | - |
| Billing period with progress bar | No | **Need billing period progress** |
| Resource breakdown (Compute, DB, Add-ons) | Yes | - |
| Individual add-on costs | Yes | - |
| Payment method card display | Partial (Stripe) | **Need card last 4 digits + expiry display** |
| Invoice history with numbers | Yes | - |
| Download invoice | No | **Need invoice PDF download** |

### 7. Deploy Templates (Marketplace)

| Stitch Design Feature | Wokku Has? | Gap? |
|---|---|---|
| Template cards with icons | Yes | - |
| Category filter pills | Yes | - |
| Search | Yes | - |
| Pricing display per template | No | **Need "Starts at $X/mo" on cards** |
| "Deploy Now" button per card | No (tap to detail first) | **Need quick deploy action** |
| Version badge (v5.82, LATEST) | No | **Need version info on templates** |
| Custom Template Engine CTA | No | **Need custom template upload** |

---

## Summary: What We're Missing vs Heroku

### Critical Gaps (must have for parity)

| Feature | Impact | Effort |
|---|---|---|
| **App metrics (P95, throughput, errors)** | High — Heroku's biggest feature | Large (need metrics collection API) |
| **Process formation display** | High — core Heroku concept | Small (Dokku ps:report) |
| **Log severity coloring** | Medium — developer experience | Small (parse log format) |
| **2FA (TOTP)** | High — security requirement | Medium |
| **"Open App" button** | High — basic UX | Tiny |
| **Add-on resource usage** | Medium — database health | Medium |
| **Billing period progress** | Medium — billing UX | Small |
| **Payment method display** | Medium — billing trust | Small |

### Nice to Have (differentiation)

| Feature | Impact |
|---|---|
| Inline sparkline charts | Visual polish |
| App version/release number on cards | Information density |
| Region/environment tags | Organization |
| Team switcher | Multi-team UX |
| Custom template upload | Power users |
| Invoice PDF download | Business users |

### What Wokku Has That Heroku Doesn't

| Feature | Advantage |
|---|---|
| **Mobile app** | Heroku has no mobile app |
| **1-click templates (51 apps)** | Heroku has no marketplace |
| **Web terminal** | Heroku only has `heroku run` CLI |
| **Database backups to S3/R2** | Heroku backups are limited |
| **Self-hosted option** | Heroku is cloud-only |
| **GitHub PR preview deploys** | Heroku Review Apps need pipeline setup |
| **Multi-provider server provisioning** | Heroku is AWS-only |
| **AI debugging** | Heroku has nothing similar |
| **5 notification channels** | Heroku has email only |

---

## Priority Implementation Order

### Phase 1: Make the app look like the design (UI only)
1. Implement the exact Stitch screen layouts in React Native
2. Match colors, typography, spacing exactly
3. Use placeholder/mock data where real data isn't available yet

### Phase 2: Add the missing backend features
1. App metrics API (response time, throughput, errors)
2. Process formation API (web.1 Standard-2X, worker.1)
3. "Open App" button (just open domain URL)
4. Log severity parsing
5. Billing period progress
6. Payment card display

### Phase 3: Advanced features
1. 2FA/TOTP
2. API key rotation
3. Add-on usage metrics
4. Custom template upload

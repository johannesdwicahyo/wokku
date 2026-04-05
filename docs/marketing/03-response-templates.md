# Wokku — Response Templates (DMs, Comments, Support)

> Copy-paste ready. Adjust tone based on platform — more casual on TikTok, more professional on LinkedIn.

---

## First Contact Responses

### "Apa itu Wokku?"
```
Wokku itu platform buat deploy aplikasi (Rails, Node, Python, apapun yang jalan di Docker) tanpa ribet sewa VPS.

Mirip Heroku, tapi:
- Harga mulai Rp 24.000/bulan (Heroku mulai Rp 113k)
- Bayar pake QRIS/transfer Indonesia
- 100 template one-click deploy
- Built on Dokku (open source), data lo tetep punya lo

wokku.dev
```

### "Wokku beda sama Heroku/Railway/Render apa?"
```
Beda paling jelas:

1. Harga: Wokku $1.50/bulan vs Heroku $7, Railway $5, Render $7
2. Payment: Wokku bisa QRIS/BCA/BNI. Yang lain cuma credit card USD
3. Bahasa: dokumentasi & support dalam Bahasa Indonesia
4. Ownership: dibangun di atas Dokku open source, lo bisa pindah kapan aja

Yang sama: deploy experience, database, scaling, dll. Wokku gak kasih fitur yang kurang, cuma harga yang disesuaikan.
```

### "Aman gak pake Wokku?"
```
Security audit 13 item sebelum launch:

✅ 2FA (TOTP)
✅ Rate limiting (anti brute force)
✅ Webhook signature verification (HMAC-SHA256)
✅ Content Security Policy
✅ DNS rebinding protection
✅ Account lockout after 10 failed logins
✅ Let's Encrypt SSL (auto)
✅ Daily backup ke S3-compatible storage
✅ Secrets dikelola via Kamal (gak di-hardcode)
✅ CSRF, XSS protection (Rails default)
✅ Encrypted database (PostgreSQL)
✅ HTTPS enforced (HSTS)
✅ Dependency scanning (Brakeman, bundler-audit)

Plus test coverage 65%+ dan CI/CD pipeline sebelum deploy.
```

### "Data saya dimana?"
```
Server Wokku di Jakarta (Tencent). Latency ke user Indonesia <10ms.

Data lo:
- Database & files: di server yang lo pilih
- Backup: ke S3-compatible storage (bisa pake punya lo, atau managed)
- Export: tinggal klik, download semua

Kalo mau pindah ke VPS sendiri, Wokku CE (Community Edition) open source. Install di VPS manapun, import data, selesai.
```

---

## Pricing Questions

### "Beneran $1.50?"
```
Iya beneran. Ini pricing tier Wokku:

- Free: 256MB RAM, sleeps after 30 min idle (buat hobby/testing)
- Basic: $1.50/mo — 512MB RAM, always-on
- Standard: $4/mo — 1GB RAM
- Performance: $8/mo — 2GB RAM
- Performance-2x: $15/mo — 4GB RAM

Database (Postgres/Redis/MySQL/dll) included gratis di semua tier paid.

Bayar bulanan, cancel kapan aja.
```

### "Kalo traffic tinggi gimana?"
```
Scale-up:
- Pindah ke tier lebih tinggi (klik, langsung)
- Atau add more instances (horizontal scaling)

Sample angka:
- Basic tier (512MB): cukup buat ~100 concurrent users Rails app
- Standard (1GB): ~300 concurrent users
- Performance (2GB): ~800 concurrent users

Kalo app lo viral sampe butuh dedicated server, lo bisa upgrade ke server dedicated (pricing custom, DM aja).
```

### "Ada trial gak?"
```
Ada 2 opsi:

1. Free tier — 256MB RAM, tidur kalo idle 30 menit. Buat coba-coba selamanya gratis.

2. Free credit Rp 50.000 — buat 100 developer pertama yang soft launch. Ini cukup buat Basic tier 2 bulan. DM gue kalo mau code-nya.
```

---

## Technical Questions

### "Dokku itu apa?"
```
Dokku adalah open-source PaaS engine (alternative ke Heroku's platform). Dia yang handle:

- Build Docker image dari kode lo
- Setup nginx reverse proxy
- Manage SSL cert (Let's Encrypt)
- Process management (scale, restart)
- Database provisioning

Dokku udah ada sejak 2013, battle-tested, dipake ribuan self-hoster.

Wokku = Dokku + web UI + managed hosting + Indonesia-specific features (QRIS, IDR, dll).

Kalo lo tech-savvy dan mau self-host: pake Dokku langsung.
Kalo lo mau managed & localized: pake Wokku.
```

### "Bisa deploy apa aja?"
```
Apapun yang jalan di Docker:

Backend:
- Ruby on Rails ✅
- Node.js (Next.js, Express, NestJS) ✅
- Python (Django, FastAPI, Flask) ✅
- Go (Gin, Fiber, Echo) ✅
- PHP (Laravel, Symfony) ✅
- Java (Spring Boot) ✅
- Rust (Axum, Actix) ✅
- Elixir (Phoenix) ✅

Frontend:
- Static sites (HTML/CSS/JS) ✅
- SSR frameworks (Next.js, Nuxt, SvelteKit) ✅

Self-hosted apps:
- WordPress, Ghost, BookStack
- n8n, WAHA, Chatwoot
- Metabase, Grafana, Plausible
- 100 template total, tinggal klik

Gak bisa:
- Apps yang butuh GPU
- Apps yang butuh specific kernel modules
- Apps yang butuh > 8GB RAM (untuk sekarang)
```

### "GitHub integration gimana?"
```
3 cara deploy:

1. Git push manual:
   `git push wokku main`

2. GitHub auto-deploy:
   Connect repo di dashboard, setiap push ke main → auto deploy

3. One-click template:
   Pilih dari 100 template, klik Deploy, selesai

Mulai minggu ini juga support GitLab dan Bitbucket (baru launch fitur).
```

---

## Comparison Questions

### "Coolify vs Wokku?"
```
Coolify: self-hosted, lo setup sendiri, lo maintain sendiri. Gratis tapi effort.

Wokku: managed, kita yang maintain. Murah tapi bukan gratis.

Trade-off:
- Mau zero cost + willing to learn DevOps → Coolify
- Mau fokus ke code, gak mau maintain server → Wokku

Plus: Coolify Januari 2026 kena 11 critical CVE (CVSS 10.0), 52.000 instance exposed. Managed service lebih aman kalo lo gak punya waktu patch security.

Wokku CE (Community Edition) juga tersedia — self-host kalo mau. Gratis.
```

### "Vercel / Netlify vs Wokku?"
```
Vercel/Netlify = bagus buat frontend (Next.js, React, static sites) dan serverless functions kecil.

Wokku = bagus buat full backend (Rails, Django, Go, Node) dan database.

Gak head-to-head, beda use case:
- Butuh CDN + frontend deploy? Vercel
- Butuh backend + database + background job? Wokku
- Butuh keduanya? Pake bareng (frontend di Vercel, backend di Wokku)
```

### "DigitalOcean App Platform vs Wokku?"
```
DO App Platform bagus kalo lo udah di ekosistem DigitalOcean.

Beda sama Wokku:
- Harga: DO mulai $5/mo, Wokku $1.50/mo
- Payment: DO credit card USD, Wokku QRIS/IDR
- Template: DO punya "marketplace" tapi kebanyakan advertising. Wokku punya 100 verified template.
- Database: DO managed $7+/mo, Wokku included gratis

Fitur level enterprise lebih ke DO. Harga + localization lebih ke Wokku.
```

---

## Objections

### "Indonesia tech startup biasanya cepet mati, Wokku juga bakal kaya gitu?"
```
Fair concern. Gue founder solo, 15 tahun freelance experience.

Yang bikin Wokku beda:

1. Bootstrapped — gak ada investor VC yang demand hockey stick growth. Bisa sustainable dengan 100-500 user.

2. Built on Dokku open source — kalo Wokku tutup besok, data lo tetep bisa lo pindahin ke VPS sendiri pake Dokku. Zero lock-in.

3. Real revenue day 1 — bukan pake model "freemium + fundraise". Tiap user bayar Rp 24k/bulan, bisnis jalan.

4. Low burn — Wokku jalan di 1 VPS kecil. Monthly cost infra < Rp 500rb.

Tapi iya, risiko selalu ada. Makanya data export built-in. Lo bisa keluar kapan aja.
```

### "Gue udah pake [tool X] yang gratis, kenapa harus bayar?"
```
Fair question. Kalo yang lo pake sekarang:
- Jalan stabil
- Lo ngerti cara maintain
- Lo gak pernah stress kalo server down
- Backup auto-jalan

Pake yang gratis aja. Seriously, gak semua orang butuh managed service.

Wokku worth it kalo:
- Lo sering lupa patch security
- Lo pernah kena data loss karena backup gak jalan
- Lo mau waktu lo dipake buat coding, bukan DevOps
- Lo punya multiple project dan capek maintain semua

Rp 24k/bulan = Rp 800/hari. Kurang dari harga kopi. Worth it kalo bikin lo gak stress.
```

### "Gue mau self-host aja, open source gak?"
```
Yes, Wokku CE (Community Edition) open source di:
github.com/johannesdwicahyo/wokku

Install di VPS sendiri, semua fitur core jalan (deploy, domain, SSL, database, log, backup).

Yang di Wokku EE (Enterprise Edition, closed source):
- Billing system (QRIS, IDR invoicing)
- Multi-team management
- Mobile app (iOS/Android)
- Priority support
- Dyno tier auto-scaling

EE cuma penting kalo lo mau jual service sendiri pake Wokku sebagai foundation. Kalo buat dipake sendiri, CE udah cukup.
```

---

## Dealing with Negative / Trolls

### "Proyek baru, pasti gak ada user nya"
```
Yep, kamu bener. Wokku baru aja soft launch. Target 100 user bulan ini, 1000 akhir tahun.

Kalo mau nungguin sampe ada 10k user, silakan. Kalo mau jadi early adopter dan dapet pricing tetap forever, pake sekarang.

First 100 user bayar Rp 24k/bulan SELAMANYA. Kalo ntar price naik ke Rp 50k, lo tetep bayar 24k.
```

### "Ah cuma wrapper doang dari Dokku"
```
Betul, Wokku = Dokku + UI + managed hosting + localized (Indonesia).

Kayak Heroku = Unix + Linux + some Ruby magic + UI + billing. Semua teknologi besar itu wrapper dari tech yang udah ada.

Value-nya bukan di core engine (Dokku open source, gratis). Value-nya di:
1. UI yang nyaman (gak usah SSH tiap command)
2. Managed infra (gak usah maintain server)
3. Localization (bayar IDR, pake QRIS)
4. Support lokal (bahasa Indonesia, WhatsApp)

Kalo lo nyaman pake Dokku langsung, silakan. Wokku buat yang mau trade sedikit biaya untuk waktu & stress.
```

### "Ngapain pake ini kalo bisa pake AWS?"
```
Kalo lo udah expert AWS, pake AWS. Wokku gak buat lo.

Wokku buat:
- Developer yang males nge-setup AWS EC2 + ALB + RDS + ElastiCache + Secrets Manager + CloudWatch + IAM
- Freelancer yang deploy client project tiap bulan, males setup infra dari nol
- Startup early-stage yang gak punya DevOps team
- Yang butuh predictable pricing (Rp 24k/bulan tetap, bukan "it depends on usage")

AWS menang di skala besar. Wokku menang di simplicity + localization.
```

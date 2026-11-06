---
title: Plan & Harga
summary: "Pilih plan. Tiap plan udah include bundle box, satu database Postgres, satu Redis cache, plus object storage — ditagih bulanan via iPaymu. Nggak ada metering, nggak ada tagihan kaget."
eyebrow: billing
badges:
  - tone: success
    label: live
last_updated: 2026-05-29
---

# Plan & Harga

Wokku punya empat plan. Tiap plan harganya **flat bulanan**, udah include bundle box (container), satu database Postgres, satu Redis cache, plus object storage — ukurannya beda per tier. Bayar sekali sebulan via iPaymu (QRIS, VA, e-wallet, atau kartu). Nggak ada metering per jam, nggak ada tagihan overage.

## Empat plan-nya

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| **Harga / bulan** | Rp 0 | Rp 75.000 | Rp 225.000 | Rp 750.000 |
| **Buat** | side project, demo | satu builder | satu developer dengan side income | tim kecil |
| **Seat termasuk** | 1 | 1 | 1 | 3 |
| **Seat tambahan** | — | — | — | Rp 45.000 / seat / bulan |
| **Free trial** | — | 7 hari | 7 hari | 7 hari |

> Solo / Pro / Team dimulai dengan **free trial 7 hari**. Kamu dapat semua fitur penuh; baru ditagih kalau lewat masa trial dan masih lanjut subscribe.

## Apa aja yang masuk di tiap plan

Plan-nya **batteries-included**: resource di bawah udah jadi satu paket sama harga plan-nya, nggak perlu beli add-on terpisah.

### Box (container)

*Box* itu satu container. App yang multi-process (Rails + Sidekiq, web + cron) bisa share satu box pakai `foreman`/`supervisor` — lihat [bundling process](/docs/scaling/bundled-processes).

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| Small (512 MB) | — | 3 | 3 | 3 |
| Medium (1 GB) | — | — | 2 | 2 |
| Large (2 GB) | — | — | — | 1 |
| Sleeping (app idle) | 3 | 3 | 3 | 3 |
| Add-on Extra Large | — | — | — | Rp 300.000 / bulan |
| Add-on Extra X-Large | — | — | — | Rp 600.000 / bulan |

### Database, cache, object storage

Tiap plan dapat **satu dari masing-masing**, ukurannya nyesuain tier.

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| Postgres | 100 MB shared | 1 GB | 5 GB | 10 GB |
| Redis (cache) | 25 MB | 100 MB | 500 MB | 1 GB |
| Object storage (MinIO) | 1 GB | 5 GB | 25 GB | 50 GB |
| Backup | manual | harian · retensi 3 hari | harian · retensi 7 hari | harian + bulanan · retensi 30 hari |

Detail tiap resource ada di [plan bundles](/docs/billing/plan-bundles).

### Fitur Pro

Tersedia di **Pro** dan **Team**:

— **PR previews** — tiap pull request dapat environment preview sendiri, otomatis dihapus pas merge
— **Transfer app** — pindahin app ke user Wokku lain (cocok buat agency)
— **Scheduled tasks** — job berulang gaya cron tanpa harus spawn worker terpisah

### Observability

Semua plan dapat log per-app, metrics, monitoring per-request, dan audit log. Retensi nyesuain plan-nya.

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| Log | 1 hari | 3 hari | 7 hari | 30 hari |
| Metrics (high-res, 1 menit) | 1 hari | 7 hari | 30 hari | 90 hari |
| Metrics (rollup per jam) | 7 hari | 30 hari | 90 hari | 365 hari |
| Audit log | ✓ | ✓ | ✓ | ✓ |

### Support

— **Free / Solo** — chatbot
— **Pro / Team** — chat sama manusia, prioritas
— **Team** — kontak dedicated

## Selalu termasuk

Semua plan, free atau paid:

— App unlimited (dalam quota box plan kamu)
— Custom domain dengan **SSL Let's Encrypt otomatis**
— Deploy lewat `git push` + GitHub auto-deploy
— Log dan metrics real-time di dashboard
— Riwayat deploy dengan rollback satu klik
— CLI, REST API, dan plugin Claude Code MCP
— Nggak ada biaya bandwidth

## Cara kerja billing

Wokku pakai **model invoice bulanan**. Nggak ada metering per jam, nggak ada saldo deposit, nggak ada line item per resource — kamu bayar satu invoice flat buat plan kamu, plus seat tambahan kalau di Team.

### Siklus bulanannya

1. Kamu pilih plan dan dapat 7 hari free trial (Solo / Pro / Team), atau tetap di Free selamanya.
2. **7 hari sebelum tanggal billing**, kami email invoice yang mau jatuh tempo plus total dan due date.
3. **Pas tanggal billing**, invoice mulai bisa dibayar. Bayar via iPaymu (QRIS, virtual account, e-wallet, atau kartu).
4. Kalau belum dibayar lewat **7 hari setelah due date**, app berbayar kamu akan di-suspend. Begitu invoice dibayar, app langsung jalan lagi — nggak ada data hilang, nggak perlu redeploy.
5. Siklus reset lagi di tanggal billing berikutnya.

Tanggal billing-nya nge-anchor ke tanggal pertama kali kamu subscribe.

### Upgrade atau downgrade

— **Upgrade mid-cycle** — kami terbitin invoice prorata buat selisihnya. Plan berubah seketika.
— **Downgrade** — dijadwalin di tanggal billing berikutnya supaya kamu masih dapat yang udah kamu bayar. Bisa juga cancel dari [billing page](/dashboard/billing) dan kamu turun ke **Free** di akhir siklus.

### Refund

Invoice yang udah dibayar nggak refundable. Kalau ada masalah di sisi kami, kami kasih credit di invoice berikutnya — nggak ribet.

## Self-hosted (gratis selamanya)

Wokku Community Edition open source di **AGPL-3.0**. Jalanin di server sendiri, nggak ada layer billing sama sekali:

```bash
git clone https://github.com/johannesdwicahyo/wokku.git
cd wokku && docker compose up -d
```

Nggak ada quota, nggak ada batas seat, nggak ada cap retensi. Kamu yang siapin hardware + ops; Wokku yang handle deploy pipeline-nya. Managed cloud di [wokku.cloud](https://wokku.cloud) buat yang nggak mau ribet ngurus VPS sendiri.

## Banding sama Heroku

| | **Wokku Solo** | **Heroku Basic** equivalent |
|---|---|---|
| 1× Small dyno + Postgres | Rp 75.000 / bln | ~Rp 450.000 / bln |
| Tambah Redis cache | included | +Rp 225.000 / bln |
| Tambah backup + retensi 7 hari | upgrade ke Pro | +Rp 105.000 / bln |
| **Total** | **Rp 75.000 / bln** (Solo) atau **Rp 225.000 / bln** (Pro) | **~Rp 780.000 / bln** |

**60–90% lebih murah** buat setup yang setara, plus billing QRIS dan infrastruktur Jakarta.

## Enterprise

Butuh plan custom, SLA, dedicated support, atau deployment on-premises? Email [enterprise@wokku.cloud](mailto:enterprise@wokku.cloud).

---
title: Edisi Open Source
summary: "Edisi OSS Wokku cuma web UI — REST API, CLI, MCP server, dan mobile app cuma ada di Cloud. Release ship monthly."
eyebrow: open source
last_updated: 2026-05-29
---

# Edisi Open Source

Wokku Cloud (site ini, `wokku.cloud`) adalah managed PaaS yang kami operasikan buat kamu. **Community Edition** di [github.com/johannesdwicahyo/wokku](https://github.com/johannesdwicahyo/wokku) adalah app Rails open-source yang bisa kamu jalanin di infrastruktur sendiri — dashboard yang sama, surface lebih kecil.

## Apa yang ada di edisi OSS

| Surface | OSS | Cloud |
|---|---|---|
| **Web UI / dashboard** | ✅ | ✅ |
| Apps, database, domain, SSL, log, metrics | ✅ | ✅ |
| Team + role-based permission | ✅ | ✅ |
| Templates gallery (one-click deploy) | ✅ | ✅ |
| **REST API** (`/api/v1/*`) | — | ✅ |
| **CLI** (`wokku` binary) | — | ✅ |
| **MCP server** (integrasi Claude Code) | — | ✅ |
| **Mobile app** (iOS / Android) | — | ✅ |
| Monthly invoice billing + plan bundle | — | ✅ |
| Shared Postgres + Redis addon | — | ✅ |
| Log persistence berbasis Vector | — | ✅ |
| Audit log / activity stream | basic | full |
| Otomasi DNS Cloudflare | — | ✅ |
| Payment iPaymu / Stripe | — | ✅ |

Web UI-nya app Rails dan design system ViewComponent yang sama. Apa pun yang kamu liat di screenshot `wokku.cloud` render persis sama di instance self-hosted kamu.

## Kenapa surface-nya nyusut

Kami unbundle CLI, API, MCP, dan mobile dari edisi OSS karena:

— **Beban maintenance** — tiap surface punya auth flow, rate limit, dan cadence release sendiri. Shipping semuanya ke self-hoster bikin tiap release OSS jadi multi-platform release.
— **Dependensi Cloud-specific** — REST API di production asumsi ada infrastruktur Cloud-side (request signing, fleet-wide rate limit, log drain). Pisahin itu rapi selalu jadi porting tax.
— **Mobile + MCP adalah service auth-gated** — keduanya call balik ke managed auth layer kami. Fork mereka supaya support OAuth per-instance nggak worth support load-nya.

Kalau kamu self-host dan butuh salah satunya, jalan ke depannya adalah upgrade ke Cloud — UI sama, model data sama, plus surface yang kami operasikan terpusat.

## Cadence release

Release OSS ship **monthly, tiap tanggal 1**. Tiap release di-tag `vYYYY.MM` (mis. `v2026.06`) dan berisi:

— Semua bug fix dari deploy Cloud bulan sebelumnya
— Penambahan fitur web-UI yang nggak bergantung ke infrastruktur Cloud-only
— Migrasi dan perubahan schema (selalu reversible)
— Entri CHANGELOG yang ringkas isinya

Kamu bisa pin ke versi tertentu, atau ikut `main` untuk yang paling baru — kami jaga `main` tetap hijau via CI, tapi cuma release ber-tag yang di-test end-to-end di clean install.

## Upgrade

```bash
cd wokku
git fetch origin
git checkout v2026.06   # atau tag terbaru
bundle install
bin/rails db:migrate
bin/kamal redeploy      # atau command deploy yang setara
```

Upgrade di-design **forward-only dan rollback-safe** dalam satu release. Kami nggak ship migration yang nggak bisa di-reverse rapi dalam satu window release.

## Lisensi

OSS adalah **AGPL-3.0**. Kamu bisa jalanin buat diri sendiri, tim, atau perusahaan. Kalau kamu fork dan modifikasi sebagai hosted service, kamu wajib kasih user source code perubahan kamu.

Kalau mau bundle edisi OSS ke produk closed-source atau jual sebagai managed service, hubungi [hello@wokku.cloud](mailto:hello@wokku.cloud) buat lisensi komersial.

## Mulai pakai OSS

```bash
git clone https://github.com/johannesdwicahyo/wokku
cd wokku
bin/setup
bin/dev
```

README punya setup lengkap termasuk PostgreSQL, Redis, setup runtime host (Docker Swarm, Caddy, wokkud), dan Cloudflare DNS (kalau perlu). Buat production, liat [docs/infra/](https://github.com/johannesdwicahyo/wokku/tree/main/docs/infra) di repo.

## Kalau butuh API atau CLI sekarang?

Jalan paling simple adalah pakai [Wokku Cloud](https://wokku.cloud) — plan gratis sudah cover satu hobby app dan termasuk full REST API, CLI, dan MCP surface.

Kalau spesifik butuh API di infrastruktur self-hosted, hubungi kami buat enterprise license — kami bisa ship service API sebagai container terpisah berdampingan dengan install web-UI OSS.

## Lihat juga

— [GitHub repo](https://github.com/johannesdwicahyo/wokku) — source, issue, release
— [Catatan Beta](/docs/beta) — status saat ini Wokku Cloud
— [FAQ](/docs/troubleshooting/faq) — perbedaan CE vs Cloud

---
title: App Sekali Klik
summary: Temukan app siap pakai, seperti CMS, tool otomasi, AI agent, atau starter framework, dan deploy dengan sekali klik.
last_updated: 2026-11-07
---

Kamu akan menemukan template, men-deploy-nya dengan nama app kamu sendiri, lalu membukanya di `https://my-app.wokku.app`.

## Temukan template

:::tabs
::web-ui
Buka **Templates** di sidebar. Halaman ini menampilkan app unggulan, lalu satu baris untuk tiap kategori. Ketik di kotak pencarian untuk memfilter berdasarkan nama, deskripsi, atau tag.

::cli
```bash
wokku templates                 # every template: slug and description
wokku templates:info ghost      # details for one template
```

::api
```bash
curl "https://wokku.cloud/api/v1/templates?q=analytics" \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

Pakai `?q=` untuk mencari atau `?category=<slug>` untuk memfilter, misalnya `?category=cms`. Kosongkan keduanya untuk menampilkan semuanya. Response-nya juga menyertakan daftar kategori.

::mcp
Minta ke Claude: *"Template Wokku apa saja yang ada untuk analytics?"*
:::

### Unggulan

| Template | Apa itu |
|---|---|
| Hermes Agent | AI agent self-hosted dengan memori persisten: bot Telegram plus dashboard web |
| n8n | Otomasi workflow, seperti Zapier |
| Ghost | Platform publishing dan blogging |
| Dify | Platform untuk membangun workflow AI dan app LLM |
| Directus | API REST dan GraphQL instan untuk database SQL |
| Listmonk | Pengelola newsletter dan mailing list |
| Nextcloud | Sinkronisasi file, kalender, dan kolaborasi |
| Umami | Analytics website yang simpel dan cepat |

### Kategori

Frameworks · Automation · Communication · Analytics · CMS & Content · Productivity · E-Commerce · Developer Tools · AI · Databases & Admin · Media · Monitoring · Security · File Storage · Links & URL · Email · RSS & Reading · Platform

Kategori **Frameworks** berisi app starter, misalnya Astro, Next.js, Rails, Django, dan Laravel. Deploy salah satunya untuk mendapatkan proyek yang sudah jalan, yang bisa kamu clone dan ubah. Untuk daftar lengkap dan terbaru, pakai **Templates** atau `wokku templates`.

## Deploy template

:::tabs
::web-ui
1. Buka template dari **Templates**.
2. Pakai nama app yang disarankan atau ketik sendiri, misalnya `my-app`.
3. Cek **what this uses**, yang menampilkan ukuran dan add-on yang dibutuhkan template.
4. Klik **Deploy &lt;template name&gt;**.

::cli
```bash
wokku deploy ghost --name my-app
```

::api
```bash
# Get your server id first: GET /api/v1/servers
curl -X POST https://wokku.cloud/api/v1/templates/deploy \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug": "ghost", "name": "my-app", "server_id": "<server-id>"}'
```

::mcp
Minta ke Claude: *"Deploy template Ghost sebagai my-app."*
:::

Wokku membuat app-nya, mengatur environment variable default dari template, serta membuat dan menghubungkan database yang dibutuhkan template. Sebagian besar template sudah live dalam 30–90 detik.

## Setelah di-deploy

- Buka `https://my-app.wokku.app`. Banyak app memintamu membuat akun admin saat pertama kali dikunjungi.
- [Ubah environment variable](/docs/apps/config) untuk mengonfigurasi app.
- [Tambahkan custom domain](/docs/domains-ssl/custom-domains). HTTPS disiapkan otomatis.
- [Cek log](/docs/monitoring/logs) kalau app-nya tidak mau jalan.

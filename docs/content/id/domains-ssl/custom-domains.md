---
title: Custom Domain & HTTPS
summary: Arahkan domain kamu sendiri ke app Wokku. HTTPS aktif dengan sendirinya setelah DNS ter-resolve.
last_updated: 2026-11-07
---

Tambahkan `www.example.com` ke `my-app`, arahkan DNS ke Wokku, dan sertifikatnya diterbitkan otomatis. Setiap app juga langsung bisa diakses di `https://my-app.wokku.app` tanpa setup apa pun.

## 1. Tambahkan domain

:::tabs
::web-ui
Buka app → **Settings → Domains** → **+ Add domain**. Masukkan hostname lalu klik **Add domain**. Panel tersebut menampilkan record DNS persis yang perlu kamu buat.

::cli
```bash
wokku domains:add my-app www.example.com
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/domains \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"hostname": "www.example.com"}'
```
:::

## 2. Arahkan DNS ke Wokku

Buat satu record di DNS provider kamu:

| Jenis domain | Record | Nilai |
|---|---|---|
| Subdomain (`www.example.com`, `app.example.com`) | `CNAME` | `my-app.wokku.app` |
| Root domain (`example.com`) | `A` | IP yang tampil di panel **Add domain** |
| Root domain, kalau provider kamu mendukung CNAME flattening | `ALIAS` / `ANAME` | `my-app.wokku.app` |

Perubahan DNS biasanya muncul dalam hitungan menit, tapi bisa sampai 24 jam.

:::callout tip
Pakai Cloudflare? Set record-nya ke **DNS only** (awan abu-abu) sampai sertifikat diterbitkan.
:::

## 3. HTTPS aktif dengan sendirinya

Wokku mengecek DNS kamu setiap beberapa menit. Begitu record mengarah ke Wokku, Wokku menerbitkan sertifikat Let's Encrypt dan memperbaruinya sebelum kedaluwarsa. Domain akan menampilkan badge **SSL** kalau sudah siap.

Request HTTP biasa selalu di-redirect ke HTTPS. Ini tidak bisa dimatikan.

Kalau DNS sudah benar tapi badge belum muncul, coba ulang secara manual:

:::tabs
::web-ui
Di **Settings → Domains**, klik **Enable SSL** di samping domain.

::cli
```bash
wokku certs:enable my-app www.example.com
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/domains/DOMAIN_ID/ssl \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Aktifkan SSL untuk www.example.com di my-app"* (tool `wokku_enable_ssl`).
:::

## Lihat dan hapus domain

:::tabs
::web-ui
Buka **Settings → Domains** lalu klik **Remove** di samping domain.

::cli
```bash
wokku domains my-app                           # list
wokku domains:remove my-app www.example.com    # remove one
wokku domains:clear my-app                     # remove every custom domain
```

::api
```bash
# DOMAIN_ID comes from the list
curl https://wokku.cloud/api/v1/apps/my-app/domains \
  -H "Authorization: Bearer $TOKEN"

curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/domains/DOMAIN_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Hapus www.example.com dari my-app"* (tool `wokku_list_domains`, `wokku_remove_domain`).
:::

## Troubleshooting

- **Badge SSL belum muncul setelah satu jam:** cek record dengan `dig www.example.com`. Hasilnya harus mengarah ke Wokku, bukan ke host lama atau proxy.
- **Error sertifikat di browser:** DNS masih propagasi, atau domain belum pernah ditambahkan ke app. Tambahkan dulu, lalu tunggu badge-nya.
- **Root domain tidak bisa pakai CNAME:** itu memang aturan DNS. Pakai record `A`, atau `ALIAS`/`ANAME` kalau provider kamu menyediakannya.

---
title: Audit Log
summary: Lihat siapa melakukan apa di workspace kamu, dari mana dan kapan — filter, export ke CSV, atau baca lewat CLI dan API.
last_updated: 2026-11-07
---

Di sini kamu bisa melihat aksi yang terjadi di workspace kamu — deploy, perubahan config, domain, database, member, billing. Buka **Activity** di sidebar.

## Isi tiap entri

| Field | Contoh |
|---|---|
| **When** | Timestamp sampai detik |
| **Who** | Member yang melakukan, atau sistem untuk aksi otomatis |
| **Action** | `app.deployed`, `config.updated`, `app.renamed` |
| **Target** | App, database, atau member yang dikenai aksi |
| **Channel** | Dashboard, CLI, API, MCP, git push, atau Webhook |

## Filter dan export

Di halaman **Activity**, filter berdasarkan **Action**, **Channel**, **User**, **Since**, dan **Until**. Filter bisa digabung, dan URL menyimpannya, jadi kamu bisa membagikan tampilan yang sudah difilter.

Klik **Export CSV** untuk mengunduh entri yang sudah difilter. Kolomnya:

```text
created_at, user_email, action, target_type, target_name, channel, metadata_json
```

## Bukti anti-manipulasi

Setiap malam Wokku menyegel entri hari itu ke dalam hash chain. Banner **verified** di halaman menampilkan hari terakhir yang disegel, jumlah entrinya, dan awal hash chain-nya. Ini membuktikan entri yang kamu lihat belum diubah sejak disegel.

## CLI dan API

:::tabs
::cli
```bash
wokku activity   # last 20 entries
```

::api
```bash
curl "https://wokku.cloud/api/v1/activities?limit=100" \
  -H "Authorization: Bearer $TOKEN"
```

Mengembalikan entri terbaru lebih dulu. `limit` bernilai 1–200 (default 50); tidak ada filter lain — pakai dashboard untuk memfilter.

::mcp
Tanya Claude: *"Apa saja yang berubah di workspace saya hari ini?"*
:::

## Lihat juga

- [Log](/docs/monitoring/logs) — output app kamu sendiri
- [Member & Role](/docs/teams/members)

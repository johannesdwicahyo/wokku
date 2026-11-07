---
title: Environment Variable
summary: Atur, lihat, dan hapus environment variable app kamu, lalu restart untuk menerapkannya.
last_updated: 2026-11-07
---

Kamu akan mengatur config var untuk app kamu dan me-restart-nya supaya berlaku.

:::callout note
Perubahan berlaku di restart atau deploy berikutnya. Restart dengan `wokku ps:restart my-app` atau tombol **restart**. Lihat [Restart / Stop / Start](/docs/apps/lifecycle).
:::

## Lihat

:::tabs
::web-ui
Buka app kamu → tab **Deploy** → **Config**.

::cli
```bash
wokku config my-app                  # all vars
wokku config:get my-app SECRET_KEY   # one var
wokku config:export my-app > .env    # as a .env file
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Tampilkan environment variable untuk my-app."*
:::

Anggota tim dengan role viewer bisa melihat nama variable, tapi tidak bisa melihat nilainya.

## Atur

:::tabs
::web-ui
Tab **Deploy** → **Config** → tambahkan key dan value → simpan.

::cli
```bash
wokku config:set my-app SECRET_KEY=abc123 LOG_LEVEL=info
```

::api
```bash
curl -X PUT https://wokku.cloud/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vars": {"SECRET_KEY": "abc123", "LOG_LEVEL": "info"}}'
```

::mcp
Minta ke Claude: *"Set LOG_LEVEL=info di my-app."*
:::

## Hapus

:::tabs
::web-ui
Tab **Deploy** → **Config** → ikon hapus di samping variable.

::cli
```bash
wokku config:unset my-app LEGACY_KEY OLD_SECRET
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["LEGACY_KEY"]}'
```

::mcp
Minta ke Claude: *"Hapus LEGACY_KEY dari my-app."*
:::

## Diatur otomatis untuk kamu

| Variable | Kapan |
|----------|------|
| `PORT` | Selalu. App kamu harus listen di port ini. |
| `DATABASE_URL` | Saat kamu menambah atau menghubungkan database Postgres, MySQL, atau MariaDB |
| `REDIS_URL` | Saat kamu menambah atau menghubungkan Redis |

Semua process type (`web`, `worker`, …) memakai variable yang sama.

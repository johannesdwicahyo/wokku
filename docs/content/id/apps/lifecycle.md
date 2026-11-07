---
title: Restart / Stop / Start
summary: Restart, stop, start, redeploy, atau hapus app.
last_updated: 2026-11-07
---

Kamu akan mengatur apakah app kamu berjalan atau tidak. Tombol-tombol di dashboard ada di tab **Overview** app kamu.

## Restart

Me-restart semua process type. Lakukan ini setelah mengubah [environment variable](/docs/apps/config).

:::tabs
::web-ui
App → **restart**.

::cli
```bash
wokku ps:restart my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/restart \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Restart my-app."*
:::

## Stop

Menghentikan semua proses. App berhenti melayani trafik sampai kamu menjalankannya lagi.

:::tabs
::web-ui
App → **stop**.

::cli
```bash
wokku ps:stop my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/stop \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Stop my-app."*
:::

## Start

:::tabs
::web-ui
App → **start**.

::cli
```bash
wokku ps:start my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/start \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Start my-app."*
:::

## Redeploy

Mem-build ulang dan men-deploy source terbaru tanpa push baru.

:::tabs
::cli
```bash
wokku redeploy my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/deploy \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Redeploy my-app."*
:::

## Hapus

Menghapus app dan container-nya. Database yang hanya terhubung ke app ini ikut dihapus; database shared tetap disimpan. Ini tidak bisa dibatalkan.

:::tabs
::web-ui
App → tab **Settings** → **Danger**.

::cli
```bash
wokku apps:destroy my-app
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app \
  -H "Authorization: Bearer $TOKEN"
```
:::

App gratis juga tidur sendiri setelah 30 menit tanpa trafik dan bangun di request berikutnya (sekitar 30 detik). Lihat [Resource](/docs/scaling/resources).

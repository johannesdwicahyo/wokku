---
title: GitHub Auto-Deploy
summary: Hubungkan repository GitHub supaya setiap push ke deploy branch kamu otomatis di-deploy.
last_updated: 2026-11-07
---

Kamu akan menginstal Wokku GitHub App, memilih repo dan branch, lalu tinggal push ke GitHub.

## Hubungkan repository

:::tabs
::web-ui
1. Buka app kamu → tab **Deploy** → **GitHub**.
2. Hanya pertama kali: klik **Install GitHub App** dan beri akses ke repo kamu.
3. Pilih repository-nya, lalu branch-nya.

::cli
Wokku GitHub App harus sudah punya akses ke repo tersebut (instal sekali dari dashboard).

```bash
wokku github:repos                                   # repos the app can see
wokku github:connect my-app your-org/your-repo --branch main
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/github_connect \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"repo": "your-org/your-repo", "branch": "main"}'
```

::mcp
Minta ke Claude: *"Hubungkan my-app ke your-org/your-repo di main."*
:::

Menghubungkan saja tidak langsung men-deploy. Push berikutnya ke branch itulah yang men-deploy.

## Cara kerjanya

1. Kamu push ke branch yang terhubung.
2. GitHub memberi tahu Wokku.
3. Wokku mem-build dan men-deploy commit tersebut. Pantau di tab **Deploy**.

## Ganti deploy branch

:::tabs
::web-ui
Di daftar **Apps**, buka panel app tersebut dan edit **Branch**.

::cli
```bash
wokku apps:update my-app --branch develop
```

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"deploy_branch": "develop"}'
```
:::

## Putuskan koneksi

:::tabs
::web-ui
Tab **Deploy** → kotak **GitHub** → **Disconnect**.

::cli
```bash
wokku github:disconnect my-app
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/github_disconnect \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Putuskan GitHub dari my-app."*
:::

Kamu tetap bisa deploy dengan `git push wokku main` setelah memutuskan koneksi.

## Lihat juga

- [Preview deploy untuk pull request](/docs/guides/preview-deploys)
- [Buat & Deploy](/docs/apps/deploy)

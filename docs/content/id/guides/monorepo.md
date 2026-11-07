---
title: Deploy dari Monorepo
summary: Deploy satu subdirektori dari repo besar sebagai app Wokku tersendiri dengan git subtree.
last_updated: 2026-11-07
---

Kamu akan push hanya satu subdirektori (misalnya `apps/api`) ke sebuah app Wokku.

## Push subtree

`git subtree` push sebuah subdirektori seolah-olah itu root repo.

```bash
# from the repo root
git subtree push --prefix apps/api wokku main
```

Kalau itu lambat atau ditolak sebagai non-fast-forward, split dulu lalu force-push:

```bash
git subtree split --prefix apps/api -b deploy-api
git push wokku deploy-api:main --force
```

`Procfile`, `Dockerfile`, dan manifest dependency kamu (`package.json`, `Gemfile`, …) harus berada di subdirektori itu, karena subdirektori itulah yang jadi root saat Wokku build.

## Beberapa app dari satu repo

Buat satu app per bagian yang di-deploy, masing-masing dengan remote sendiri:

```bash
wokku apps:create my-api
wokku apps:create my-web
git remote add wokku-api git@git.wokku.cloud:my-api
git remote add wokku-web git@git.wokku.cloud:my-web
git subtree push --prefix apps/api wokku-api main
git subtree push --prefix apps/web wokku-web main
```

:::callout note
GitHub auto-deploy build dari root repo. Untuk monorepo, pakai subtree push (dari mesin kamu atau CI).
:::

## Troubleshooting

- **"Updates were rejected"**: pakai cara split dan `--force` di atas.
- **Bahasa yang terdeteksi salah**: manifest harus ada di root subdirektori.
- **Shared package tidak ada**: subtree push hanya membawa folder itu. Salin kode bersama ke dalamnya, atau pakai [Dockerfile](/docs/guides/dockerfile) di root subdirektori.

## Langkah selanjutnya

- [Deploy dengan Dockerfile](/docs/guides/dockerfile)
- [Create & Deploy](/docs/apps/deploy)

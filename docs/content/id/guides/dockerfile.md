---
title: Deploy dengan Dockerfile
summary: Commit sebuah Dockerfile dan Wokku akan build app kamu dari situ, bukan dari deteksi otomatis.
last_updated: 2026-11-07
---

Kamu akan menambahkan `Dockerfile` di root repo dan push. Wokku otomatis build dari file itu. Tanpa Dockerfile, Wokku mendeteksi bahasa kamu secara otomatis dengan Nixpacks.

## 1. Tambahkan Dockerfile

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
CMD ["node", "server.js"]
```

`server.js` harus listen di `process.env.PORT`.

:::callout warning
**Listen di `$PORT`.** Wokku men-set `PORT` dan mengirim traffic ke situ. `EXPOSE` tidak mengubah port, dan port yang di-hardcode adalah penyebab paling umum deploy Docker yang berhasil build tapi tidak melayani apa-apa.
:::

## 2. Deploy

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Pantau build-nya di tab **Deploy** milik app.

## 3. Process type tambahan

`Procfile` tetap bisa dipakai. Setiap baris dijalankan dari image hasil build:

```procfile
web: node server.js
worker: node worker.js
```

Scale process type tambahan dengan `wokku ps:scale my-app worker=1`. Lihat [Background Workers](/docs/guides/background-workers).

## Migration

Tidak ada release phase. Jalankan migration setelah deploy:

```bash
wokku run my-app -- node migrate.js
```

Jangan taruh baris `release:` di Procfile kamu. Baris itu akan jadi process type, bukan langkah sekali jalan.

## Tips

- Base image yang slim dan multi-stage build menghasilkan image lebih kecil yang deploy-nya lebih cepat.
- Salin lockfile dan install dependency sebelum menyalin source, supaya layer itu di-cache.
- Jangan tanam secret ke dalam image. Set sebagai [environment variable](/docs/apps/config).

## Troubleshooting

- **Berhasil build tapi tidak ada respons**: app tidak listen di `$PORT`.
- **Dockerfile diabaikan**: nama file harus `Dockerfile` dan berada di root repo.

## Langkah selanjutnya

- [Environment Variables](/docs/apps/config)
- [Log](/docs/monitoring/logs)

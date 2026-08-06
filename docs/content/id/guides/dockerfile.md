# Deploy dengan Dockerfile

Saat buildpack tidak cukup — dependency sistem kustom, build multi-stage, base
image yang spesifik — commit `Dockerfile` dan Wokku mem-build aplikasimu dari
situ.

## Cara kerja

Jika `Dockerfile` ada di root repo-mu, Wokku memakainya otomatis saat `git push`
— tanpa buildpack, tanpa config. Kamu memiliki seluruh build.

## 1. Tambah Dockerfile

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

:::callout warn
**Listen di port yang kamu `EXPOSE`, dan baca `$PORT` jika aplikasimu mendukung.**
Wokku memetakan traffic masuk ke port yang di-expose. Hardcode port lain adalah
alasan paling umum deploy Docker berhasil build tapi tidak menyajikan apa pun.
:::

## 2. Deploy

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Wokku mendeteksi `Dockerfile`, mem-build image di server-mu, dan menjalankannya.
Pantau build di [logs](/docs/apps/logs)-mu.

## 3. Banyak proses

`Procfile` tetap bekerja dengan deploy Dockerfile — deklarasikan process type
tambahan dan mereka jalan dari image yang dibuild:

```procfile
web: node server.js
worker: node worker.js
```

## 4. Jalankan migration saat release

```procfile
release: node migrate.js
web: node server.js
```

Proses `release` jalan setelah build sukses, sebelum traffic dialihkan.

## Tips

- **Image lebih kecil deploy lebih cepat** — pakai base slim/alpine dan build multi-stage.
- **Cache dependency** — copy lockfile dan install sebelum copy source (seperti di atas).
- **Jangan tanam secret** — set sebagai [config var](/docs/apps/config), baca saat runtime.

## Troubleshooting

- **Berhasil build tapi tidak ada respons** — `EXPOSE` dan listen di port yang sama; utamakan `$PORT`.
- **Build lambat tiap kali** — susun ulang layer agar install dependency ter-cache.
- **Wokku malah pakai buildpack** — pastikan `Dockerfile` ada di root repo.

## Langkah berikutnya

- [Environment Variables](/docs/apps/config) · [Logs](/docs/apps/logs)

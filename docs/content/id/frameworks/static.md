---
title: Situs Statis
summary: Sajikan HTML/CSS/JS biasa atau output build tool (Vite, Hugo, Eleventy) di Wokku.
last_updated: 2026-11-07
---

Beri tahu Nixpacks bahwa situsnya statis, atau sajikan output build dengan Node server kecil, lalu push.

## File biasa (tanpa langkah build)

Tambahkan `Staticfile` di root repo. Nixpacks lalu menyajikan file-filenya dengan nginx. Kalau file-filenya ada di subfolder, sebutkan nama foldernya:

```yaml
# Staticfile
root: public    # omit if the files are at the repo root
```

Ini hanya berlaku kalau repo tidak punya `package.json`. Kalau ada, Nixpacks mem-build-nya sebagai app Node.

## Dengan langkah build (Vite, dll.)

Build, lalu sajikan folder output-nya di `$PORT`:

```bash
npm install serve
```

```json
"scripts": { "build": "vite build", "start": "serve -s dist -l $PORT" }
```

```procfile
web: npm start
```

`-s` mengembalikan `index.html` untuk path yang tidak dikenal, yang dibutuhkan single-page app untuk deep link. Hilangkan untuk situs multi-halaman.

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **404 di semua halaman** — `root:` di `Staticfile` harus mengarah ke folder yang berisi `index.html`. Dengan langkah build, sajikan folder output (`dist`, `build`), bukan source-nya.
- **Deep link SPA 404** — tambahkan `-s` ke `serve`.

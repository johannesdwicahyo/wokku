# Deploy Situs Statis

Deploy HTML/CSS/JS biasa atau output build tool apa pun (Vite, SPA biasa, Hugo,
Eleventy) ke Wokku.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Folder berisi file statis (atau build yang menghasilkannya)

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-site`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-site --server my-server
```
:::

## 2. Beri tahu Wokku bahwa ini statis

Tambahkan `Staticfile` kosong di root dari yang ingin disajikan. Secara default
root repo yang disajikan; set `root:` jika file-mu ada di subfolder:

```yaml
# Staticfile
root: public        # hilangkan jika file ada di root repo
```

Selesai — static buildpack menyajikan file-mu lewat HTTP, dengan clean URL dan gzip.

## 3. Dengan langkah build (Vite, dll.)

Jika build dulu, pakai Node buildpack dan sajikan output-nya:

```text
# package.json
"scripts": { "build": "vite build", "start": "npx serve dist -l $PORT" }
```

```procfile
web: npm start
```

## 4. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-site
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-site
git push wokku main
```
:::

Live di `https://my-site.wokku.app`.

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **404 di mana-mana** — cek `root:` di `Staticfile` menunjuk ke file-mu.
- **Deep link SPA 404** — tambahkan fallback agar route tak dikenal menyajikan `index.html` (mode SPA).
- **Output build tidak disajikan** — dengan langkah build, sajikan folder output (`dist`/`build`), bukan source.

## Langkah berikutnya

- [Domain Kustom](/docs/domains-ssl/custom-domains) · [Logs](/docs/apps/logs)

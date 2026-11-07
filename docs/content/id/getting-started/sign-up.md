---
title: Daftar
summary: Buat akun Wokku kamu di browser, lalu kalau mau, login dari CLI atau Claude.
last_updated: 2026-11-07
---

Kamu akan membuat akun di wokku.cloud dan, kalau mau, menghubungkan CLI atau Claude ke akun itu.

## Buat akun kamu

1. Buka [wokku.cloud](https://wokku.cloud) dan klik **Get Started**.
2. Pilih cara mendaftar:
   - **Email and password**
   - **Google**
   - **GitHub**
   - **Apple**
3. Kamu langsung masuk ke dashboard, siap untuk [deploy pertama](/docs/getting-started/first-deploy).

Akun hanya bisa dibuat di browser. CLI dan API login ke akun yang sudah kamu punya.

## Login dari tool lain (opsional)

:::tabs
::cli
```bash
gem install wokku-cli
wokku auth:login       # opens your browser to approve the login
wokku auth:whoami      # check who you're signed in as
```

Lihat [Instal CLI](/docs/cli/install).

::api
Buat token di **Settings → API Tokens**, lalu kirim sebagai bearer token:

```bash
curl https://wokku.cloud/api/v1/auth/whoami \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

Lihat [Autentikasi](/docs/api/authentication).

::mcp
Plugin Claude Code memakai API token. Buat token di **Settings → API Tokens**, lalu ikuti [Setup Claude Code](/docs/mcp/setup).
:::

## Aktifkan autentikasi dua faktor

Buka **Settings → Security** dan klik **Enable 2FA**. Scan kodenya dengan aplikasi authenticator apa saja.

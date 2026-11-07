---
title: Instal CLI
summary: Instal tool command-line wokku, sign in, lalu cek apakah sudah jalan.
eyebrow: cli
last_updated: 2026-11-07
---

Instal CLI lewat RubyGems, sign in lewat browser, lalu jalankan command pertamamu.

## Instal

CLI ini berupa Ruby gem. Kamu butuh Ruby 3.2 atau yang lebih baru.

```bash
gem install wokku-cli
```

## Sign in

```bash
wokku auth:login
```

Command ini membuka browser. Setujui kode yang muncul di terminal, lalu CLI menyimpan sesimu secara lokal.

## Cek apakah sudah jalan

```bash
wokku version      # prints the CLI version
wokku auth:whoami  # shows who you are signed in as
wokku doctor       # checks your sign-in, CLI version and your apps
```

## Pakai di CI

Di CI tidak ada browser, jadi pakai API token. Buat token di **Profile → API Tokens** di dashboard (atau dengan `wokku tokens:create ci`), lalu set sebagai environment variable:

```bash
export WOKKU_API_TOKEN=your-token
wokku apps
```

## Update dan uninstall

```bash
gem update wokku-cli
gem uninstall wokku-cli
```

## Selanjutnya

- [Semua command](/docs/cli/commands) — atau jalankan `wokku help`
- [Setup Claude Code](/docs/mcp/setup)
- Tambahkan `--json` ke command baca untuk output yang bisa dibaca mesin, atau `--quiet` untuk menyembunyikan pesan status.

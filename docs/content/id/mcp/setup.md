---
title: Setup Claude Code
summary: Instal plugin Wokku supaya Claude Code bisa deploy dan mengelola app kamu.
eyebrow: claude code
last_updated: 2026-11-07
---

Instal plugin Wokku di Claude Code, beri API token, lalu minta Claude mengurus app kamu pakai bahasa sehari-hari.

## Sebelum mulai

- Akun Wokku
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Ruby 3.0 atau yang lebih baru (plugin hanya memakai standard library, tanpa gem)
- API token dari **Profile → API Tokens** di dashboard

## Instal

Di Claude Code, jalankan:

```text
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

Atau dari terminal:

```bash
claude plugin marketplace add johannesdwicahyo/wokku-plugin
claude plugin install wokku@wokku
```

Saat diminta **Wokku API Token**, tempel token kamu. Lalu restart Claude Code.

:::callout tip
Buat token di **Profil → API tokens**. Pilih **Read-only** kalau Claude cukup melihat (status, log, nama config), atau **Full access** supaya Claude bisa deploy dan mengubah sesuatu. Plugin hanya memakai token ini, tidak pernah login [CLI](/docs/cli/install) kamu.
:::

## Coba

Buka Claude Code di project kamu dan tanyakan:

- *"List my Wokku apps"*
- *"Deploy this project to Wokku as my-app"*
- *"Add a free Postgres to my-app"*
- *"Show the logs for my-app"*
- *"Why did my last deploy of my-app fail?"*
- *"Add blog.example.com to my-app and enable SSL"*
- *"Scale my-app to 2 web processes"*
- *"Roll back my-app to the previous release"*
- *"Is anything down right now?"*

Claude akan minta konfirmasi sebelum melakukan hal yang destruktif, seperti menghapus app atau me-restore backup.

## Apa saja isinya

- **109 tool** yang mencakup app, deploy, config, domain, database, backup, scaling, monitoring, insiden, tim, dan billing. Lihat [Tool yang tersedia](/docs/mcp/tools).
- **4 skill terpandu** untuk alur kerja umum:

| Skill | Fungsinya |
|---|---|
| `/wokku:deploy-new-app` | Buat app, set config, tambah database, dan pandu kamu sampai `git push` |
| `/wokku:troubleshoot` | Cek status, log, kesehatan, dan deploy, lalu sarankan perbaikan |
| `/wokku:setup-github-deploy` | Hubungkan repo GitHub supaya deploy setiap ada push |
| `/wokku:add-database` | Tambah database ke app dan set variable URL-nya |

## Troubleshooting

| Masalah | Solusi |
|---|---|
| "Plugin not found" | Jalankan command `marketplace add` dulu. |
| "Invalid or expired token" | Buat token baru di **Profile → API Tokens** lalu instal ulang plugin. |
| Tool tidak muncul | Restart Claude Code, lalu cek `claude plugin list` menampilkan `wokku@wokku` dalam status enabled. |
| Skill tidak dipakai | Sebut namanya: *"Use the wokku deploy-new-app skill"*. |
| Ada masalah lain | Minta *"Run wokku doctor"* — ini mengecek token, versi plugin, dan kesehatan app kamu. |

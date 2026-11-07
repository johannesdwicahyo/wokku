---
title: Deploy dengan Claude (MCP)
summary: Biarkan Claude membuat, men-deploy, dan menjalankan app Wokku kamu lewat permintaan dalam bahasa sehari-hari.
last_updated: 2026-11-07
---

Kamu akan menghubungkan Claude Code ke Wokku, lalu memintanya deploy dengan bahasa sehari-hari.

## 1. Hubungkan Claude Code

Pilih salah satu:

**Dengan Wokku CLI** (memakai token CLI yang sedang login):

```bash
gem install wokku-cli
wokku auth:login
wokku mcp:install
```

**Dengan plugin marketplace Claude Code:**

```text
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

Kamu akan diminta `WOKKU_API_TOKEN`. Restart Claude Code setelah memakai salah satu cara. Detailnya di [MCP Setup](/docs/mcp/setup).

## 2. Minta Claude untuk deploy

> *"Buat app bernama my-app dengan Postgres shared, set `RAILS_ENV=production`, lalu deploy project ini."*

Claude memanggil tool Wokku satu per satu dan melaporkan setiap hasilnya.

## Apa saja yang bisa kamu minta

| Tugas | Contoh |
|---|---|
| Buat dan deploy | *"Deploy template Ghost sebagai my-blog"* |
| Database | *"Tambahkan Redis shared ke my-app"* |
| Config | *"Set `LOG_LEVEL=debug` di my-app"* |
| Pantau | *"Tampilkan 100 baris log terakhir my-app"* |
| Scale | *"Scale my-app ke 2 web dan 1 worker"* |
| Operasikan | *"Rollback my-app ke release sebelumnya"* |
| Domain | *"Tambahkan api.example.com ke my-app"* |

Daftar lengkapnya ada di [MCP Tools](/docs/mcp/tools).

## Ganti atau hapus

```bash
wokku mcp:switch     # push your current CLI token after a new auth:login
wokku mcp:logout     # remove the Wokku MCP server from Claude Code
```

## Troubleshooting

- **"install Claude Code first"**: perintah `claude` harus ada di PATH kamu.
- **Error autentikasi**: jalankan `wokku auth:login`, lalu `wokku mcp:switch`, lalu restart Claude Code.
- **Tool tidak ditemukan**: update plugin-nya (`/plugin` di Claude Code), atau jalankan ulang `wokku mcp:install`.

## Langkah selanjutnya

- [MCP Setup](/docs/mcp/setup)
- [MCP Tools](/docs/mcp/tools)
- [Perintah CLI](/docs/cli/commands)

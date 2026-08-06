# Deploy dengan Claude (MCP)

Wokku menyediakan server Model Context Protocol (MCP), jadi agen AI seperti
Claude bisa provisioning dan mengoperasikan aplikasimu dalam bahasa biasa —
buat aplikasi, tambah database, deploy, cek logs dan vitals — tanpa kamu keluar
dari editor.

## 1. Setup server MCP

Install ke Claude Code dengan token CLI Wokku-mu:

```bash
wokku mcp:install
```

Ini mendaftarkan server MCP Wokku ke Claude Code memakai token aktifmu. Detail
lengkap di [MCP Setup](/docs/mcp/setup); tool yang tersedia ada di
[MCP Tools](/docs/mcp/tools).

## 2. Minta Claude men-deploy

Setelah terhubung, cukup jelaskan keinginanmu:

> *"Buat aplikasi bernama `my-api` di server-ku, tambah database Postgres, set
> `RAILS_ENV=production`, lalu deploy."*

Claude memanggil tool Wokku secara berurutan — `create_app`, `create_database`,
`set_config`, `deploy_app` — dan melaporkan tiap hasilnya.

## Yang bisa Claude lakukan

| Tugas | Contoh prompt |
|---|---|
| Buat & deploy | *"Deploy blog Ghost bernama my-blog di server 1"* |
| Database | *"Tambah instance Redis ke my-api dan link"* |
| Config | *"Set `LOG_LEVEL=debug` di my-api"* |
| Observasi | *"Tampilkan 100 baris log terakhir my-api"* · *"Bagaimana vitals my-api?"* |
| Scale | *"Scale my-api jadi 2 web dan 1 worker"* |
| Operasi | *"Rollback my-api ke release sebelumnya"* |
| Domain | *"Tambah domain api.example.com ke my-api dengan SSL"* |

Permukaan MCP mencerminkan [CLI](/docs/cli/commands) dan
[API](/docs/api/endpoints) — apa pun yang bisa kamu script, Claude bisa jalankan.

## Ganti atau sign out

```bash
wokku mcp:switch     # arahkan ulang ke token / endpoint aktif
wokku mcp:logout     # hapus server MCP
```

## Troubleshooting

- **"install Claude Code first"** — CLI `claude` harus ada di PATH-mu; install Claude Code, lalu jalankan ulang `wokku mcp:install`.
- **Error auth** — token CLI-mu mungkin kedaluwarsa; autentikasi ulang via CLI dan jalankan `wokku mcp:switch`.
- **Tool tidak ketemu** — update plugin: jalankan ulang `wokku mcp:install` untuk refresh server terdaftar.

## Langkah berikutnya

- [MCP Setup](/docs/mcp/setup) · [MCP Tools](/docs/mcp/tools) · [CLI](/docs/cli/commands)

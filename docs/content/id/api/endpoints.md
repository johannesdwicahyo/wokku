---
title: Endpoint API
summary: Indeks singkat REST API per tugas. Spesifikasi OpenAPI adalah referensi lengkapnya.
eyebrow: api
last_updated: 2026-11-07
---

Cari endpoint yang kamu butuhkan, lalu lihat parameter dan response-nya di spesifikasi lengkap.

- **Base URL:** `https://wokku.cloud/api/v1`
- **Auth:** `Authorization: Bearer <token>` — lihat [Autentikasi](/docs/api/authentication)
- **Referensi lengkap:** [`/api/v1/openapi.yaml`](https://wokku.cloud/api/v1/openapi.yaml) (OpenAPI 3; muat ke Postman, Insomnia, atau client generator)

Path di bawah relatif terhadap base URL. Path app dan database menerima ID atau nama.

:::callout note
Membuat app (`POST /apps`) butuh `server_id`. Ambil `id` dari `GET /servers`. Dashboard, CLI, dan Claude Code mengisinya otomatis untukmu.
:::

## App

| Method | Path | Fungsinya |
|---|---|---|
| GET, POST | `/apps` | Daftar app, buat app |
| GET, PATCH, DELETE | `/apps/:id` | Tampilkan, update, atau hapus app |
| POST | `/apps/:id/restart`, `/stop`, `/start` | Restart, stop, atau start |
| PATCH | `/apps/:id/rename` | Ganti nama |
| POST | `/apps/:id/clone` | Salin pengaturan ke app baru |
| POST | `/apps/:id/lock`, `/unlock` | Blokir atau izinkan deploy |
| PATCH | `/apps/:id/https`, `/cdn`, `/maintenance` | Redirect HTTPS, proxy CDN, maintenance mode |
| POST | `/apps/:id/transfer` | Tawarkan app ke user lain |
| GET | `/app_transfers` | Daftar transfer |
| POST, DELETE | `/app_transfers/:id/accept`, `/decline`, `/app_transfers/:id` | Terima, tolak, atau batalkan |

## Deploy dan release

| Method | Path | Fungsinya |
|---|---|---|
| POST | `/apps/:id/deploy` | Redeploy source terbaru |
| GET, POST | `/apps/:app_id/deploys` | Daftar deploy, mulai deploy |
| GET | `/apps/:app_id/deploys/:id` | Tampilkan deploy beserta log-nya |
| POST | `/apps/:app_id/deploys/uploads` | Upload arsip source untuk di-deploy |
| GET | `/apps/:app_id/releases`, `/releases/:id` | Daftar atau tampilkan release |
| POST | `/apps/:app_id/releases/:id/rollback` | Rollback |
| POST | `/ai/diagnose` | Diagnosis AI untuk deploy yang gagal |
| POST, DELETE | `/apps/:id/github_connect`, `/github_disconnect` | Hubungkan atau putuskan GitHub |
| GET | `/github/repos` | Repo yang bisa dilihat Wokku GitHub App |
| GET, DELETE | `/apps/:app_id/previews`, `/previews/:pr_number` | Daftar atau hapus preview PR |
| PATCH | `/apps/:id/preview_settings` | Preview on/off dan pilihan database |

## Config, proses, dan task

| Method | Path | Fungsinya |
|---|---|---|
| GET, PATCH, DELETE | `/apps/:app_id/config` | Baca, set, atau unset env var |
| GET, PATCH | `/apps/:app_id/ps` | Tampilkan atau scale proses |
| GET, PATCH | `/apps/:app_id/dynos`, `/dynos/:id` | Ukuran proses; resize tipe proses |
| GET | `/dyno_tiers` | Ukuran dan harga yang tersedia |
| POST | `/apps/:id/run` | Mulai command sekali jalan |
| GET | `/apps/:app_id/runs/:id` | Cek status run sekali jalan |
| GET, POST, DELETE | `/apps/:app_id/scheduled_tasks`, `/scheduled_tasks/:id` | Scheduled task |
| POST, DELETE | `/apps/:app_id/dev_sessions`, `/dev_sessions/:id` | Sesi dev lokal |

## Domain

| Method | Path | Fungsinya |
|---|---|---|
| GET, POST | `/apps/:app_id/domains` | Daftar atau tambah (`{"hostname": "…"}`) |
| DELETE | `/apps/:app_id/domains/:id` | Hapus |
| POST | `/apps/:app_id/domains/:id/ssl` | Terbitkan sertifikat |

## Log dan monitoring

| Method | Path | Fungsinya |
|---|---|---|
| GET | `/apps/:app_id/logs` | Log (`lines`, `since`, `until`, `level`, `q`) |
| GET | `/apps/:id/metrics`, `/monitor`, `/vitals` | CPU/memori, statistik request, Web Vitals |
| POST | `/apps/:id/vitals/rotate_token` | Token web-vitals baru |
| GET | `/apps/:app_id/checks` | Status health check |
| GET | `/incidents`, `/incidents/:id` | Gangguan |
| GET, POST, DELETE | `/alert_mutes`, `/alert_mutes/:id` | Mute alert HP |
| GET, POST, DELETE | `/notifications`, `/notifications/:id` | Channel notifikasi |
| POST | `/notifications/:id/test` | Kirim pesan tes |
| GET | `/activities` | Feed aktivitas (`limit`, maks 200) |
| GET | `/doctor` | Self-check token, client, dan app |

## Add-on dan database

| Method | Path | Fungsinya |
|---|---|---|
| GET | `/apps/:app_id/addons` | Daftar add-on sebuah app |
| POST, DELETE | `/apps/:app_id/addons/shared`, `/shared/:engine` | Tambah atau hapus add-on shared gratis |
| POST | `/apps/:app_id/addons/dedicated` | Upgrade ke add-on dedicated |
| DELETE | `/apps/:app_id/addons/:id` | Hapus add-on dedicated |
| GET, POST | `/databases` | Daftar atau buat database |
| GET, DELETE | `/databases/:id` | Tampilkan atau hapus |
| POST | `/databases/:id/link`, `/unlink` | Hubungkan ke atau putuskan dari app |
| PATCH | `/databases/:id/resize` | Resize database dedicated |
| POST | `/databases/:id/import`, `/retry` | Import dump; coba ulang provisioning |
| GET | `/databases/:id/monitor` | Koneksi, cache hit, ukuran, query |
| GET, POST | `/databases/:database_id/backups` | Daftar backup, backup sekarang |
| GET | `/databases/:database_id/backups/:id/download` | Link download |
| POST | `/databases/:database_id/backups/:id/restore` | Restore |

## Template

| Method | Path | Fungsinya |
|---|---|---|
| GET | `/templates`, `/templates/:id` | Daftar atau tampilkan template |
| POST | `/templates/deploy` | Deploy template |

## Akun dan tim

| Method | Path | Fungsinya |
|---|---|---|
| GET | `/auth/whoami` | User saat ini |
| GET, POST, DELETE | `/auth/tokens`, `/auth/tokens/:id` | API token |
| POST | `/auth/device/code`, `/auth/device/token` | Sign in lewat browser untuk tool |
| GET, POST, DELETE | `/ssh_keys`, `/ssh_keys/:id` | SSH key |
| GET, POST | `/teams` | Daftar atau buat tim |
| GET, POST, PATCH, DELETE | `/teams/:team_id/members`, `/members/:id` | Anggota tim dan role |
| POST, DELETE | `/devices`, `/devices/:id` | Daftarkan HP untuk push alert |
| POST | `/account/deletion` | Hapus akun kamu |
| GET | `/servers` | Server yang bisa kamu deploy (untuk `server_id`) |
| GET | `/meta` | Versi API dan versi client minimum (tanpa auth) |

## Billing

| Method | Path | Fungsinya |
|---|---|---|
| GET | `/billing/current_plan` | Plan dan batasanmu |
| GET | `/billing/invoices` | Invoice |

---
title: Tool yang Tersedia
summary: Semua tool Wokku yang bisa dipanggil Claude Code, dikelompokkan per tugas.
eyebrow: claude code
last_updated: 2026-11-07
---

Lihat apa saja yang bisa dilakukan Claude di Wokku. Kamu jarang perlu memanggil tool ini berdasarkan nama — cukup minta pakai bahasa sehari-hari dan Claude memilih tool-nya. Tool yang menghapus atau menimpa data akan minta konfirmasi dulu.

## App

| Tool | Fungsinya |
|---|---|
| `wokku_list_apps` | Daftar app kamu |
| `wokku_get_app` | Tampilkan detail app |
| `wokku_create_app` | Buat app |
| `wokku_update_app` | Ubah pengaturan app (nama, branch deploy) |
| `wokku_rename_app` | Ganti nama app (alamat wokku.app-nya ikut berubah) |
| `wokku_clone_app` | Salin pengaturan app ke app baru (tanpa environment variable atau data) |
| `wokku_lock_app` | Blokir deploy baru |
| `wokku_unlock_app` | Izinkan deploy lagi |
| `wokku_delete_app` | Hapus app |
| `wokku_transfer_app` | Tawarkan app ke user lain lewat email |
| `wokku_list_transfers` | Daftar transfer masuk dan keluar |
| `wokku_accept_transfer` | Terima transfer |
| `wokku_decline_transfer` | Tolak transfer |
| `wokku_cancel_transfer` | Batalkan transfer yang kamu mulai |

## Deploy dan release

| Tool | Fungsinya |
|---|---|
| `wokku_deploy_app` | Build ulang dan deploy kode terbaru |
| `wokku_deploy_tarball` | Deploy folder lokal tanpa git push |
| `wokku_list_deploys` | Daftar deploy |
| `wokku_get_deploy` | Tampilkan deploy beserta log-nya |
| `wokku_ai_diagnose` | Tanya AI kenapa deploy gagal |
| `wokku_list_releases` | Daftar release |
| `wokku_get_release` | Tampilkan release |
| `wokku_rollback` | Rollback ke sebuah release |

## GitHub dan preview

| Tool | Fungsinya |
|---|---|
| `wokku_list_github_repos` | Daftar repo (atau branch) yang bisa dilihat Wokku GitHub App |
| `wokku_github_connect` | Deploy setiap ada push ke repo GitHub |
| `wokku_github_disconnect` | Putuskan repo GitHub |
| `wokku_list_previews` | Daftar preview app untuk pull request |
| `wokku_set_preview_settings` | Nyalakan atau matikan preview dan pilih database-nya |
| `wokku_destroy_preview` | Hapus preview app |

## Config

| Tool | Fungsinya |
|---|---|
| `wokku_get_config` | Tampilkan environment variable |
| `wokku_set_config` | Set environment variable |
| `wokku_unset_config` | Hapus environment variable |

## Menjalankan dan scaling

| Tool | Fungsinya |
|---|---|
| `wokku_restart_app` | Restart |
| `wokku_stop_app` | Stop |
| `wokku_start_app` | Start |
| `wokku_get_ps` | Tampilkan proses yang sedang jalan |
| `wokku_scale_app` | Ubah jumlah tiap proses yang jalan |
| `wokku_get_dynos` | Tampilkan ukuran dan biaya bulanan tiap tipe proses |
| `wokku_list_box_sizes` | Daftar ukuran dan harga |
| `wokku_resize_app` | Ubah CPU dan RAM sebuah tipe proses |
| `wokku_run_command` | Jalankan command sekali jalan dan tunggu output-nya |
| `wokku_get_run` | Cek status run sekali jalan |
| `wokku_list_scheduled_tasks` | Daftar scheduled task |
| `wokku_create_scheduled_task` | Tambah scheduled task |
| `wokku_delete_scheduled_task` | Hapus scheduled task |

## Log dan monitoring

| Tool | Fungsinya |
|---|---|
| `wokku_doctor` | Cek token, versi plugin, kesehatan host, dan status app dalam satu panggilan |
| `wokku_get_logs` | Baca log |
| `wokku_get_app_metrics` | CPU dan memori (satu jam dan satu hari terakhir) |
| `wokku_get_app_monitor` | Total request dan URL paling lambat (24 jam terakhir) |
| `wokku_get_app_vitals` | Core Web Vitals (7 hari terakhir) |
| `wokku_rotate_vitals_token` | Terbitkan token web-vitals baru |
| `wokku_list_incidents` | Daftar gangguan (default yang masih terbuka) |
| `wokku_get_incident` | Tampilkan satu insiden |
| `wokku_list_alert_mutes` | Daftar mute alert HP |
| `wokku_mute_alerts` | Mute alert HP untuk sebuah app atau event |
| `wokku_unmute_alerts` | Hapus mute |
| `wokku_list_notifications` | Daftar channel notifikasi |
| `wokku_create_notification` | Tambah channel notifikasi |
| `wokku_test_notification` | Kirim pesan tes |
| `wokku_delete_notification` | Hapus channel notifikasi |
| `wokku_list_activities` | Aktivitas terbaru |

## Domain dan HTTPS

| Tool | Fungsinya |
|---|---|
| `wokku_list_domains` | Daftar domain |
| `wokku_add_domain` | Tambah custom domain |
| `wokku_remove_domain` | Hapus domain |
| `wokku_enable_ssl` | Terbitkan sertifikat SSL untuk domain |
| `wokku_set_https` | Nyalakan atau matikan redirect HTTP → HTTPS |
| `wokku_set_cdn` | Nyalakan atau matikan proxy CDN Cloudflare |
| `wokku_set_maintenance` | Nyalakan atau matikan maintenance mode |

## Add-on dan database

| Tool | Fungsinya |
|---|---|
| `wokku_list_addons` | Daftar add-on sebuah app |
| `wokku_enable_shared_addon` | Tambah postgres, mariadb atau redis shared gratis |
| `wokku_disable_shared_addon` | Hapus add-on shared beserta datanya |
| `wokku_upgrade_dedicated_addon` | Pindahkan add-on shared ke container dedicated sendiri |
| `wokku_remove_addon` | Hapus add-on dedicated beserta datanya |
| `wokku_list_databases` | Daftar database |
| `wokku_get_database` | Tampilkan database |
| `wokku_create_database` | Buat database dedicated |
| `wokku_link_database` | Hubungkan database ke app |
| `wokku_unlink_database` | Putuskan database dari app |
| `wokku_import_database` | Import dump (menimpa database) |
| `wokku_resize_database` | Resize database dedicated |
| `wokku_retry_database` | Coba ulang database yang tertahan di status error |
| `wokku_delete_database` | Hapus database |
| `wokku_get_database_monitor` | Koneksi, cache hit rate, ukuran, dan top query |
| `wokku_list_backups` | Daftar backup |
| `wokku_create_backup` | Backup sekarang |
| `wokku_get_backup_download_url` | Ambil link download berumur pendek |
| `wokku_restore_backup` | Restore backup (menimpa database) |

## Template satu klik

| Tool | Fungsinya |
|---|---|
| `wokku_list_templates` | Daftar template satu klik |
| `wokku_get_template` | Tampilkan template |
| `wokku_deploy_template` | Deploy template |

## Akun dan tim

| Tool | Fungsinya |
|---|---|
| `wokku_whoami` | Tampilkan akun yang sedang sign in |
| `wokku_list_api_tokens` | Daftar API token |
| `wokku_create_api_token` | Buat API token |
| `wokku_revoke_api_token` | Cabut API token |
| `wokku_list_ssh_keys` | Daftar SSH key |
| `wokku_add_ssh_key` | Tambah SSH key |
| `wokku_remove_ssh_key` | Hapus SSH key |
| `wokku_list_teams` | Daftar tim |
| `wokku_create_team` | Buat tim |
| `wokku_list_team_members` | Daftar anggota |
| `wokku_add_team_member` | Undang anggota |
| `wokku_update_team_member` | Ubah role anggota |
| `wokku_remove_team_member` | Hapus anggota |

## Billing

| Tool | Fungsinya |
|---|---|
| `wokku_get_current_plan` | Tampilkan plan dan batasannya |
| `wokku_list_invoices` | Daftar invoice (bayar di dashboard) |

Lihat [Setup Claude Code](/docs/mcp/setup) untuk menginstal plugin.

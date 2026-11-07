---
title: Command CLI
summary: Semua command wokku yang akan kamu pakai, dikelompokkan per tugas, lengkap dengan argumennya.
eyebrow: cli
last_updated: 2026-11-07
---

Cari command untuk tugas yang kamu butuhkan. `APP` adalah nama app kamu (misalnya `my-app`) dan `DB` adalah nama database. Jalankan `wokku help` untuk melihat daftar yang sama di terminal.

Tambahkan `--json` ke command baca mana pun untuk output yang bisa dibaca mesin, atau `--quiet` (`-q`) untuk menyembunyikan pesan status.

## Akun

| Command | Fungsinya |
|---|---|
| `wokku auth:login` | Sign in lewat browser |
| `wokku auth:logout` | Sign out dan cabut token sesi ini |
| `wokku auth:whoami` | Tampilkan akun yang sedang sign in |
| `wokku tokens` | Daftar API token kamu |
| `wokku tokens:create NAME` | Buat API token (hanya ditampilkan sekali) |
| `wokku tokens:revoke TOKEN_ID` | Cabut API token |
| `wokku ssh-keys` | Daftar SSH key kamu |
| `wokku ssh-keys:add [PATH] --name LABEL` | Upload public key (default `~/.ssh/id_ed25519.pub`) |
| `wokku ssh-keys:remove NAME` | Hapus key (atau `--fingerprint SHA`) |
| `wokku doctor` | Cek sign-in, versi CLI, dan kesehatan app sekaligus |
| `wokku version` | Tampilkan versi CLI |

## App

| Command | Fungsinya |
|---|---|
| `wokku apps` | Daftar app kamu |
| `wokku apps:info APP` | Tampilkan detail app |
| `wokku apps:create NAME` | Buat app. Flag: `--branch BRANCH`, `--box-size SIZE`, `--shared postgres,redis`, `--dedicated-db postgres\|mysql\|mongodb`, `--dedicated-redis` |
| `wokku apps:update APP --branch BRANCH` | Ganti branch deploy |
| `wokku apps:rename APP NEW_NAME` | Ganti nama app (alamat `wokku.app`-nya ikut berubah) |
| `wokku apps:clone APP NEW_NAME` | Salin pengaturan app (tanpa environment variable atau data) |
| `wokku apps:lock APP` / `apps:unlock APP` | Blokir atau izinkan deploy baru |
| `wokku apps:transfer APP EMAIL` | Tawarkan app ke user lain |
| `wokku transfers` | Daftar transfer yang menunggu kamu atau orang lain |
| `wokku transfers:accept ID` / `:decline ID` / `:cancel ID` | Jawab atau batalkan transfer |
| `wokku apps:destroy APP` | Hapus app (minta konfirmasi) |

## Deploy dan release

| Command | Fungsinya |
|---|---|
| `wokku deploys APP` | Daftar deploy |
| `wokku deploys:info APP DEPLOY_ID` | Tampilkan deploy beserta build log-nya |
| `wokku deploy:tarball APP [DIR]` | Deploy folder lokal tanpa `git push` |
| `wokku redeploy APP` | Build ulang dan deploy source terbaru |
| `wokku releases APP` | Daftar release |
| `wokku releases:info APP RELEASE_ID` | Tampilkan satu release |
| `wokku rollback APP RELEASE_ID` | Rollback ke sebuah release |
| `wokku ai:diagnose APP [DEPLOY_ID]` | Tanya AI kenapa deploy gagal |

## GitHub dan preview

| Command | Fungsinya |
|---|---|
| `wokku github:repos [OWNER/REPO]` | Daftar repo yang bisa dilihat Wokku GitHub App, atau branch sebuah repo |
| `wokku github:connect APP OWNER/REPO [--branch BRANCH]` | Deploy setiap ada push ke repo |
| `wokku github:disconnect APP` | Berhenti deploy dari GitHub |
| `wokku previews APP` | Daftar preview app untuk pull request |
| `wokku previews:settings APP --on\|--off [--database empty\|snapshot\|shared]` | Nyalakan atau matikan preview dan pilih database-nya |
| `wokku previews:destroy APP PR_NUMBER` | Hapus preview app |

## Config

| Command | Fungsinya |
|---|---|
| `wokku config APP` | Tampilkan environment variable |
| `wokku config:get APP KEY` | Tampilkan satu variable |
| `wokku config:set APP KEY=VALUE ...` | Set variable (restart app untuk menerapkannya) |
| `wokku config:unset APP KEY ...` | Hapus variable |
| `wokku config:export APP` | Cetak variable sebagai file `.env` |

## Menjalankan dan scaling

| Command | Fungsinya |
|---|---|
| `wokku ps APP` | Tampilkan proses yang sedang jalan |
| `wokku ps:restart APP` / `ps:stop APP` / `ps:start APP` | Restart, stop, atau start app |
| `wokku ps:scale APP web=2 worker=1` | Ubah jumlah tiap proses yang jalan |
| `wokku ps:dynos APP` | Tampilkan ukuran dan biaya tiap tipe proses |
| `wokku ps:sizes` | Daftar ukuran yang tersedia |
| `wokku ps:resize APP TYPE --memory MB [--cpu N]` | Ubah CPU dan RAM sebuah tipe proses |
| `wokku run APP -- COMMAND` | Jalankan command sekali jalan, mis. `wokku run my-app -- bin/rails db:migrate` |
| `wokku run:status APP RUN_ID` | Cek status run sekali jalan |
| `wokku ps:exec APP -- COMMAND` | Jalankan command interaktif di container sekali pakai |
| `wokku enter APP` | Buka shell di container yang sedang jalan |
| `wokku cron APP` | Daftar scheduled task |
| `wokku cron:add APP --schedule '0 3 * * *' --command 'CMD' [--description 'TEXT']` | Tambah scheduled task |
| `wokku cron:remove APP TASK_ID` | Hapus scheduled task |

## Log dan monitoring

| Command | Fungsinya |
|---|---|
| `wokku logs APP [--lines N] [-f]` | Tampilkan log; `-f` (`--follow`) untuk streaming |
| `wokku metrics APP` | CPU dan memori terbaru |
| `wokku monitor APP` | Total request dan URL paling lambat |
| `wokku vitals APP` | Core Web Vitals (p75) |
| `wokku vitals:rotate-token APP` | Terbitkan token web-vitals baru |
| `wokku incidents [--all] [--app APP]` | Daftar gangguan (default yang masih terbuka) |
| `wokku incidents:info ID` | Tampilkan satu insiden |
| `wokku alerts:mutes` | Daftar mute alert HP kamu |
| `wokku alerts:mute [--app APP] [--event EVENT] [--for 1h\|8h\|1d]` | Mute alert HP |
| `wokku alerts:unmute ID` | Hapus mute |
| `wokku notifications` | Daftar channel notifikasi |
| `wokku notifications:add --team TEAM_ID --channel email --events EVENT1,EVENT2` | Tambah notifikasi email |
| `wokku notifications:test ID` | Kirim pesan tes |
| `wokku notifications:remove ID` | Hapus channel |
| `wokku activity` | Aktivitas terbaru |

## Domain dan HTTPS

| Command | Fungsinya |
|---|---|
| `wokku domains APP` | Daftar domain |
| `wokku domains:add APP DOMAIN` | Tambah custom domain |
| `wokku domains:remove APP DOMAIN` | Hapus domain |
| `wokku domains:clear APP` | Hapus semua custom domain |
| `wokku certs:enable APP DOMAIN` | Terbitkan sertifikat Let's Encrypt |
| `wokku https APP` / `https:on APP` / `https:off APP` | Lihat atau atur redirect HTTP → HTTPS |
| `wokku cdn APP` / `cdn:on APP` / `cdn:off APP` | Lihat atau atur proxy CDN Cloudflare |
| `wokku maintenance APP` / `maintenance:on APP` / `maintenance:off APP` | Lihat atau atur maintenance mode |

## Add-on dan database

| Command | Fungsinya |
|---|---|
| `wokku addons APP` | Daftar add-on sebuah app |
| `wokku addons:shared:enable APP ENGINE` | Tambah `postgres`, `mariadb` atau `redis` shared gratis |
| `wokku addons:shared:disable APP ENGINE` | Hapus add-on shared beserta datanya |
| `wokku addons:dedicated:upgrade APP ENGINE` | Pindahkan add-on shared ke container dedicated sendiri |
| `wokku addons:remove APP ADDON_ID` | Hapus add-on dedicated beserta datanya |
| `wokku databases` | Daftar database kamu |
| `wokku databases:info DB` | Tampilkan detail database |
| `wokku databases:create NAME --type postgres` | Buat database dedicated |
| `wokku databases:link DB APP [--alias ALIAS]` | Hubungkan database ke app (mengisi variable URL-nya) |
| `wokku databases:unlink DB APP` | Putuskan database dari app |
| `wokku databases:connect DB` | Buka client database interaktif |
| `wokku databases:import DB FILE` | Import dump (menimpa database) |
| `wokku databases:resize DB --cpu 0.5 --memory 1024 --disk 10` | Resize database dedicated (disk hanya bisa bertambah) |
| `wokku databases:retry DB` | Coba ulang database yang tertahan di status error |
| `wokku databases:destroy DB` | Hapus database |
| `wokku db:monitor DB` | Koneksi, cache hit rate, ukuran, dan slow query |
| `wokku backups DB` | Daftar backup |
| `wokku backups:capture DB` | Backup sekarang |
| `wokku backups:download DB BACKUP_ID [FILE]` | Download backup |
| `wokku backups:restore DB BACKUP_ID` | Restore backup (menimpa database) |

## Template satu klik

| Command | Fungsinya |
|---|---|
| `wokku templates` | Daftar template |
| `wokku templates:info SLUG` | Tampilkan template |
| `wokku deploy SLUG [--name NAME]` | Deploy template |

## Tim

| Command | Fungsinya |
|---|---|
| `wokku teams` | Daftar tim kamu |
| `wokku teams:create NAME` | Buat tim |
| `wokku teams:members TEAM_ID` | Daftar anggota |
| `wokku teams:members:add TEAM_ID --email EMAIL [--role member\|admin]` | Tambah anggota |
| `wokku teams:members:role TEAM_ID MEMBERSHIP_ID viewer\|member\|admin` | Ubah role anggota |
| `wokku teams:members:remove TEAM_ID MEMBERSHIP_ID` | Hapus anggota |

## Billing

| Command | Fungsinya |
|---|---|
| `wokku billing:plan` | Tampilkan plan dan batasannya |
| `wokku billing:invoices` | Daftar invoice (bayar di dashboard) |

## Development lokal

| Command | Fungsinya |
|---|---|
| `wokku dev APP -- COMMAND` | Jalankan command lokal dengan env production app dan tunnel database read-only. Flag: `--duration MIN`, `--rw`, `--local-port N` |
| `wokku tunnel PORT [--subdomain NAME]` | Bagikan port lokal lewat URL HTTPS publik |

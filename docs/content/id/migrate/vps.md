---
title: Migrasi dari VPS
summary: Ganti nginx, systemd, certbot, dan deploy manual di VPS dengan git push ke Wokku.
last_updated: 2026-11-07
---

Wokku itu managed: kamu push kode, dan Wokku yang menjalankan server, routing, dan HTTPS. Buat app listen di `$PORT`, pindahkan config dan data, lalu alihkan DNS.

## Apa menggantikan apa

| Di VPS kamu | Di Wokku |
|---|---|
| systemd unit / pm2 | Baris `web:` di `Procfile` |
| nginx reverse proxy | Routing bawaan ke `$PORT` |
| Perpanjangan certbot | HTTPS otomatis ([Custom Domains](/docs/domains-ssl/custom-domains)) |
| `git pull` + script restart | `git push wokku main` (build, lalu restart) |
| Runtime yang di-install manual | `Dockerfile` kamu, atau deteksi otomatis Nixpacks |
| `crontab` | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| `.env` di server | [Environment Variables](/docs/apps/config) |
| Postgres/MySQL lokal | [Add-on database](/docs/databases/create-link) |

## 1. Pastikan app bisa di-build

- Stack standar: ikuti [panduan framework](/docs/frameworks/index) kamu. Nixpacks akan mendeteksi bahasanya.
- Butuh system package yang tidak umum: commit sebuah [Dockerfile](/docs/guides/dockerfile).

Apa pun caranya, app harus **listen di `$PORT`** pada `0.0.0.0`. Sudah tidak ada nginx di depannya.

## 2. Buat app dan salin config

```bash
wokku apps:create my-app
wokku config:set my-app KEY1=value1 KEY2=value2
```

Salin nilai dari file `.env` kamu atau baris `Environment=` di systemd.

## 3. Pindahkan database

```bash
# on the VPS
pg_dump "postgres://user:pass@localhost/dbname" --no-owner --no-acl -Fc -f dump.bin

# on your machine (after copying dump.bin down)
wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app                          # note the database name
wokku databases:import <database-name> dump.bin
```

Untuk MySQL/MariaDB, import file `mysqldump` dengan cara yang sama. Lihat [Memindahkan database](/docs/migrate/index).

## 4. Deploy dan alihkan DNS

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Cek `https://my-app.wokku.app`, tambahkan domain kamu, arahkan DNS ke Wokku, dan matikan VPS setelah traffic sudah pindah.

## Hal yang perlu diperhatikan

- **File lokal** — upload dan file SQLite di disk harus dipindah ke [object storage](/docs/databases/object-storage) atau database. Disk app bersifat sementara.
- **Script cron** — ubah jadi [scheduled tasks](/docs/guides/scheduled-tasks) atau process `worker`.
- **Port dan path yang di-hardcode** — listen di `$PORT`, dan jangan berasumsi ada nginx atau struktur direktori yang tetap.

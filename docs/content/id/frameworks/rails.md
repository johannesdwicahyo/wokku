# Deploy Ruby on Rails

Deploy aplikasi Rails ke Wokku dengan Postgres, migration saat release, dan
precompile aset ditangani otomatis.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Rails dengan `Gemfile`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-rails-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-rails-app --server my-server
```
:::

## 2. Siapkan aplikasi Rails-mu

Ruby buildpack mendeteksi Rails dari `Gemfile`-mu dan precompile aset otomatis.
Tambahkan `Procfile`:

```procfile
web: bin/rails server -p $PORT -e $RAILS_ENV
release: bin/rails db:migrate
```

Proses `release` menjalankan migration setelah build sukses, sebelum traffic
dialihkan — deploy tanpa downtime.

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config**:

| Key | Value |
|---|---|
| `RAILS_MASTER_KEY` | isi `config/master.key` |
| `RAILS_ENV` | `production` |
| `RAILS_SERVE_STATIC_FILES` | `true` |
| `RAILS_LOG_TO_STDOUT` | `true` |

::cli
```bash
wokku config:set my-rails-app \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  RAILS_ENV=production RAILS_SERVE_STATIC_FILES=true RAILS_LOG_TO_STDOUT=true
```
:::

:::callout warn
Jangan pernah commit `config/master.key`. Set sebagai config var (di atas) —
Wokku menyimpannya terenkripsi.
:::

## 4. Tambahkan database

```bash
wokku addons:create postgres my-rails-app
```

Wokku menyuntikkan `DATABASE_URL`, yang dibaca Rails secara native di production.
Lihat [Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-rails-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-rails-app
git push wokku main
```
:::

Live di `https://my-rails-app.wokku.app`.

## Background job

Jalankan Sidekiq/Solid Queue sebagai proses kedua — tambahkan `worker:` ke
`Procfile`-mu lalu scale. Lihat [Bundled Processes](/docs/scaling/bundled-processes).

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — `RAILS_MASTER_KEY` salah/kosong.
- **Aset 404** — set `RAILS_SERVE_STATIC_FILES=true` (atau pakai CDN).
- **Migration tidak jalan** — pastikan baris `release:` dan cek deploy logs.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)

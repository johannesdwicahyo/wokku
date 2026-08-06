# Deploy Go

Deploy layanan web Go ke Wokku. Buildpack meng-compile modulmu jadi satu binary
— build cepat, runtime mungil.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Go dengan `go.mod`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-go-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-go-app --server my-server
```
:::

## 2. Siapkan aplikasi Go-mu

Go buildpack mendeteksi `go.mod` dan mem-build package main. Listen di `$PORT`:

```go
port := os.Getenv("PORT")
if port == "" { port = "8080" }
log.Fatal(http.ListenAndServe(":"+port, nil))
```

Jika package `main`-mu tidak di root repo, deklarasikan dengan `Procfile`:

```procfile
web: bin/my-go-app
```

Buildpack memberi nama binary sesuai segmen path terakhir modulmu. Kamu juga
bisa commit `Dockerfile` untuk kontrol penuh — Wokku memakainya otomatis bila ada.

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config** → tambahkan config yang dibaca layananmu dari env.

::cli
```bash
wokku config:set my-go-app ENV=production
```
:::

## 4. Tambahkan database (opsional)

```bash
wokku addons:create postgres my-go-app
```

Baca `os.Getenv("DATABASE_URL")` di setup `database/sql` / `pgx`-mu. Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-go-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-go-app
git push wokku main
```
:::

Live di `https://my-go-app.wokku.app`.

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **Crash saat boot** — listen di `os.Getenv("PORT")`, bukan port tetap.
- **Binary salah yang jalan** — tambahkan `Procfile` yang menunjuk `bin/<name>` yang benar.
- **Build tidak ketemu main** — pastikan `package main` + `func main()` terjangkau dari `go.mod`.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)

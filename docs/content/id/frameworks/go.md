---
title: Go
summary: Jalankan web service Go di Wokku, di-build oleh Nixpacks jadi satu binary.
last_updated: 2026-11-07
---

Listen di `$PORT`, push, dan service-mu langsung live. Mau repo yang sudah jalan dulu? Deploy starter `go` dari [Templates](/docs/templates/browse).

## Listen di `$PORT`

```go
port := os.Getenv("PORT")
if port == "" {
	port = "8080" // local dev
}
log.Fatal(http.ListenAndServe(":"+port, nil))
```

## Build dan start

Nixpacks mendeteksi `go.mod`, mem-build package `main`-mu jadi binary bernama `out`, lalu menjalankannya. Kamu tidak perlu Procfile. Kalau mau menambahkannya, arahkan ke binary itu:

```procfile
web: ./out
```

Kalau package `main`-mu tidak ada di root repo (misalnya `cmd/server`), atau kamu butuh cgo atau library sistem, commit sebuah [Dockerfile](/docs/guides/dockerfile) saja. Wokku otomatis memakainya.

## Database (opsional)

```bash
wokku addons:shared:enable my-app postgres
```

Baca `os.Getenv("DATABASE_URL")` dengan `pgx` atau `database/sql`. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **Crash atau tidak pernah merespons** — listen di `os.Getenv("PORT")`, bukan port tetap.
- **Build tidak menemukan `main`** — `package main` dengan `func main()` harus ada di root repo, atau pakai Dockerfile.
- **`bin/<name>: not found`** — binary dari Nixpacks adalah `./out`; perbaiki Procfile-nya.

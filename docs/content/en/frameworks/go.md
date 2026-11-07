---
title: Go
summary: Run a Go web service on Wokku, built by Nixpacks into a single binary.
last_updated: 2026-11-07
---

Listen on `$PORT`, push, and the service is live. Want a working repo first? Deploy the `go` starter from [Templates](/docs/templates/browse).

## Listen on `$PORT`

```go
port := os.Getenv("PORT")
if port == "" {
	port = "8080" // local dev
}
log.Fatal(http.ListenAndServe(":"+port, nil))
```

## Build and start

Nixpacks detects `go.mod`, builds your `main` package into a binary named `out`, and runs it. You don't need a Procfile. If you add one, point it at that binary:

```procfile
web: ./out
```

If your `main` package isn't at the repo root (for example `cmd/server`), or you need cgo or system libraries, commit a [Dockerfile](/docs/guides/dockerfile) instead. Wokku uses it automatically.

## Database (optional)

```bash
wokku addons:shared:enable my-app postgres
```

Read `os.Getenv("DATABASE_URL")` with `pgx` or `database/sql`. See [Create & Link a Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **Crashes or never responds** — listen on `os.Getenv("PORT")`, not a fixed port.
- **Build can't find `main`** — `package main` with `func main()` must be at the repo root, or use a Dockerfile.
- **`bin/<name>: not found`** — the Nixpacks binary is `./out`; fix the Procfile.

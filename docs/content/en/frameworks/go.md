# Deploy Go

Deploy a Go web service to Wokku. The buildpack compiles your module into a
single binary — fast builds, tiny runtime.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Go app with `go.mod`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-go-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-go-app --server my-server
```
:::

## 2. Prepare your Go app

The Go buildpack detects `go.mod` and builds the main package. Listen on `$PORT`:

```go
port := os.Getenv("PORT")
if port == "" { port = "8080" }
log.Fatal(http.ListenAndServe(":"+port, nil))
```

If your `main` package isn't at the repo root, declare it with a `Procfile`:

```procfile
web: bin/my-go-app
```

The buildpack names the binary after your module's last path segment. You can
also commit a `Dockerfile` for full control — Wokku uses it automatically when present.

## 3. Set environment variables

:::tabs
::web-ui
App → **Config** → add any config your service reads from the env.

::cli
```bash
wokku config:set my-go-app ENV=production
```
:::

## 4. Add a database (optional)

```bash
wokku addons:create postgres my-go-app
```

Read `os.Getenv("DATABASE_URL")` in your `database/sql` / `pgx` setup. See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-go-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-go-app
git push wokku main
```
:::

Live at `https://my-go-app.wokku.app`.

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **Crashes on boot** — listen on `os.Getenv("PORT")`, not a fixed port.
- **Wrong binary started** — add a `Procfile` pointing at the right `bin/<name>`.
- **Build can't find main** — ensure `package main` + `func main()` are reachable from `go.mod`.

## Next steps

- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)

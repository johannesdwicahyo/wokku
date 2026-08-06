# Add Postgres + Redis

Wire a database and a cache to one app. Wokku provisions each add-on and
injects a connection URL as a config var automatically.

## 1. Add Postgres

:::tabs
::web-ui
App → **Resources → Add-ons** → **Postgres** → choose **Shared** (free, included)
or **Dedicated** (paid) → link to the app.

::cli
```bash
wokku addons:create postgres my-app
```
:::

This sets `DATABASE_URL` on your app. Read it directly:

```text
DATABASE_URL=postgres://user:pass@host:5432/dbname
```

## 2. Add Redis

:::tabs
::web-ui
App → **Resources → Add-ons** → **Redis** → link to the app.

::cli
```bash
wokku addons:create redis my-app
```
:::

This sets `REDIS_URL`.

## 3. Read them in your app

| Language | Pattern |
|---|---|
| Node | `process.env.DATABASE_URL` / `process.env.REDIS_URL` |
| Python | `os.environ["DATABASE_URL"]` / `os.environ["REDIS_URL"]` |
| Ruby | `ENV["DATABASE_URL"]` / `ENV["REDIS_URL"]` |
| Go | `os.Getenv("DATABASE_URL")` |

Most frameworks (Rails, Django via `dj-database-url`, Laravel, Prisma) read
`DATABASE_URL` natively. See your [framework guide](/docs/frameworks/index).

## 4. Verify the connection

```bash
wokku config my-app | grep -E "DATABASE_URL|REDIS_URL"
```

Open a shell or console to test live:

```bash
wokku run my-app -- bin/rails dbconsole     # example
```

## Shared vs Dedicated

- **Shared** (free tier): a tenant on a shared cluster with a size cap. Great for
  side projects and getting started.
- **Dedicated** (paid): an isolated instance with more resources. Upgrade any time —
  see [Dedicated Upgrade](/docs/databases/dedicated-upgrade).

## Troubleshooting

- **`DATABASE_URL` missing** — the add-on must be **linked** to the app, not just created.
- **SSL errors connecting to Postgres** — append `?sslmode=require` (or your driver's equivalent) if your client demands TLS.
- **Hit the size cap** — shared tenants have a quota; upgrade to dedicated.

## Next steps

- [Backups](/docs/databases/backups) · [Supported Engines](/docs/databases/engines)

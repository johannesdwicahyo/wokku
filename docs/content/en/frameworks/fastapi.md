# Deploy FastAPI

Deploy a FastAPI app to Wokku with Uvicorn workers and Postgres.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A FastAPI app with `requirements.txt`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-fastapi-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-fastapi-app --server my-server
```
:::

## 2. Prepare your FastAPI app

```text
# requirements.txt
fastapi
uvicorn[standard]
gunicorn
psycopg[binary]
```

Add a `Procfile` (assuming `app` is your FastAPI instance in `main.py`):

```procfile
web: gunicorn main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT
```

:::callout note
Gunicorn + Uvicorn workers gives you multiple processes for production. For a
single worker, `uvicorn main:app --host 0.0.0.0 --port $PORT` also works.
:::

## 3. Set environment variables

:::tabs
::web-ui
App → **Config** → add any secrets/config your app reads from the env.

::cli
```bash
wokku config:set my-fastapi-app ENV=production
```
:::

## 4. Add a database (optional)

```bash
wokku addons:create postgres my-fastapi-app
```

Read `os.environ["DATABASE_URL"]` (SQLAlchemy/SQLModel/asyncpg). See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-fastapi-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-fastapi-app
git push wokku main
```
:::

Live at `https://my-fastapi-app.wokku.app` — docs at `/docs` (Swagger UI).

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **502 / no response** — make sure the bind uses `$PORT`, not a fixed port.
- **`UvicornWorker` not found** — add `uvicorn[standard]` to `requirements.txt`.
- **Async DB driver** — use `asyncpg` (not `psycopg`) for async SQLAlchemy.

## Next steps

- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)

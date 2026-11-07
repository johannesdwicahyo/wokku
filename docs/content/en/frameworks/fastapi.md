---
title: FastAPI
summary: Run a FastAPI app on Wokku with Gunicorn and Uvicorn workers.
last_updated: 2026-11-07
---

Add a Gunicorn start command bound to `$PORT`, push, and the API is live. Want a working repo first? Deploy the `fastapi` starter from [Templates](/docs/templates/browse).

## Dependencies

```text
# requirements.txt
fastapi
uvicorn[standard]
gunicorn
```

## Start command

Assuming your app object is `app` in `main.py`:

```procfile
web: gunicorn main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT
```

For a single process, `web: uvicorn main:app --host 0.0.0.0 --port $PORT` also works.

## Database (optional)

```bash
wokku addons:shared:enable my-app postgres
```

Read `os.environ["DATABASE_URL"]` in SQLAlchemy or SQLModel. Async drivers need the URL scheme changed (`postgresql+asyncpg://`). See [Create & Link a Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`, with interactive API docs at `/docs`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **502 / no response** — the bind must use `$PORT`, not a fixed port.
- **`UvicornWorker` not found** — add `uvicorn[standard]` to `requirements.txt`.
- **Migrations (Alembic)** — run them after deploys: `wokku run my-app -- alembic upgrade head`.

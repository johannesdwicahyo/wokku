---
title: Django
summary: Run a Django app on Wokku with Gunicorn, Postgres and WhiteNoise for static files.
last_updated: 2026-11-07
---

Add Gunicorn and WhiteNoise, read settings from the environment, push, then run migrations. Want a working repo first? Deploy the `django` starter from [Templates](/docs/templates/browse).

## Dependencies

```text
# requirements.txt
django
gunicorn
psycopg[binary]
whitenoise
dj-database-url
```

## Settings

```python
# settings.py
import os
import dj_database_url

SECRET_KEY = os.environ["SECRET_KEY"]
DEBUG = os.environ.get("DEBUG") == "True"
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")
CSRF_TRUSTED_ORIGINS = [f"https://{h}" for h in ALLOWED_HOSTS if h]
DATABASES = {"default": dj_database_url.config(conn_max_age=600)}

MIDDLEWARE.insert(1, "whitenoise.middleware.WhiteNoiseMiddleware")  # right after SecurityMiddleware
STATIC_ROOT = BASE_DIR / "staticfiles"
```

## Start command

Collect static files on boot, then start Gunicorn. A Procfile line with `&&` runs without a shell, so put both steps in a script:

```bash
#!/usr/bin/env bash
# bin/start  (chmod +x bin/start)
set -e
python manage.py collectstatic --noinput
exec gunicorn myproject.wsgi --bind 0.0.0.0:$PORT --log-file -
```

```procfile
web: bin/start
```

## Config and database

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  SECRET_KEY="$(python -c 'import secrets; print(secrets.token_urlsafe(50))')" \
  DJANGO_SETTINGS_MODULE=myproject.settings \
  ALLOWED_HOSTS=my-app.wokku.app
```

The Postgres add-on sets `DATABASE_URL`, which `dj-database-url` reads. See [Create & Link a Database](/docs/databases/create-link).

## Deploy and migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- python manage.py migrate --noinput
```

Run the migrate command after every deploy that adds migrations. Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Custom domain

After you add a [custom domain](/docs/domains-ssl/custom-domains), append it to `ALLOWED_HOSTS` (comma-separated) and restart: `wokku ps:restart my-app`.

## Troubleshooting

- **`DisallowedHost` or CSRF failures** — the hostname is missing from `ALLOWED_HOSTS`.
- **CSS/JS 404** — check the WhiteNoise middleware and `STATIC_ROOT`, and that `collectstatic` succeeded in the [logs](/docs/monitoring/logs).
- **Celery** — add `worker: celery -A myproject worker` to the Procfile and scale it. See [Background Workers](/docs/guides/background-workers).

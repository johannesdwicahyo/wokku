# Deploy Django

Deploy a Django app to Wokku with Postgres, automatic migrations, and static
files served via WhiteNoise.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Django project with `requirements.txt`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-django-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-django-app --server my-server
```
:::

## 2. Prepare your Django app

The Python buildpack detects `requirements.txt`. Make sure these are present:

```text
# requirements.txt
django
gunicorn
psycopg[binary]
whitenoise
dj-database-url
```

Add a `Procfile`:

```procfile
web: gunicorn myproject.wsgi --log-file -
release: python manage.py migrate --noinput
```

In `settings.py`, read the database + host from the environment and let
WhiteNoise serve static files:

```python
import dj_database_url, os
DATABASES = {"default": dj_database_url.config(conn_max_age=600)}
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")
MIDDLEWARE = ["whitenoise.middleware.WhiteNoiseMiddleware", *MIDDLEWARE]
STATIC_ROOT = BASE_DIR / "staticfiles"
```

:::callout note
`collectstatic` runs automatically during the Python build. The `release:`
process applies migrations after the build, before traffic shifts.
:::

## 3. Set environment variables

:::tabs
::web-ui
App → **Config**:

| Key | Value |
|---|---|
| `SECRET_KEY` | a long random string |
| `DJANGO_SETTINGS_MODULE` | `myproject.settings` |
| `ALLOWED_HOSTS` | `my-django-app.wokku.app` |
| `DEBUG` | `False` |

::cli
```bash
wokku config:set my-django-app \
  SECRET_KEY="$(python -c 'import secrets;print(secrets.token_urlsafe(50))')" \
  DJANGO_SETTINGS_MODULE=myproject.settings \
  ALLOWED_HOSTS=my-django-app.wokku.app DEBUG=False
```
:::

## 4. Add a database

```bash
wokku addons:create postgres my-django-app
```

Wokku injects `DATABASE_URL`; `dj-database-url` reads it automatically. See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-django-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-django-app
git push wokku main
```
:::

Live at `https://my-django-app.wokku.app`.

## 6. Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — remember to add the new
hostname to `ALLOWED_HOSTS` and redeploy.

## Troubleshooting

- **`DisallowedHost`** — add your domain to `ALLOWED_HOSTS` and redeploy.
- **CSS/JS 404 in production** — confirm WhiteNoise middleware + `STATIC_ROOT`; `collectstatic` must succeed in the build log.
- **Migrations didn't run** — check the `release:` line and the deploy logs.

## Next steps

- [Background workers (Celery)](/docs/scaling/bundled-processes)
- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)

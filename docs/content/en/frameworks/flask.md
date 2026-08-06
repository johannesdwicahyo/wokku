# Deploy Flask

Deploy a Flask app to Wokku with Gunicorn and Postgres.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Flask app with `requirements.txt`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-flask-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-flask-app --server my-server
```
:::

## 2. Prepare your Flask app

Include `gunicorn` in `requirements.txt`:

```text
flask
gunicorn
psycopg[binary]
```

Add a `Procfile` (assuming your app object is `app` in `app.py`):

```procfile
web: gunicorn app:app
```

If you use Flask-Migrate, add a release step:

```procfile
release: flask db upgrade
```

## 3. Set environment variables

:::tabs
::web-ui
App → **Config** → add `SECRET_KEY` and any config your app reads from the env.

::cli
```bash
wokku config:set my-flask-app SECRET_KEY="$(python -c 'import secrets;print(secrets.token_urlsafe(32))')"
```
:::

## 4. Add a database (optional)

```bash
wokku addons:create postgres my-flask-app
```

Read `os.environ["DATABASE_URL"]` in your SQLAlchemy config. See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-flask-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-flask-app
git push wokku main
```
:::

Live at `https://my-flask-app.wokku.app`.

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **`ModuleNotFoundError`** — make sure the dependency is in `requirements.txt`.
- **App object not found** — match `gunicorn app:app` to your module and variable names.
- **DB connection refused** — confirm the Postgres add-on is linked and `DATABASE_URL` is set.

## Next steps

- [Background workers](/docs/scaling/bundled-processes) · [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)

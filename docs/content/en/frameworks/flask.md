---
title: Flask
summary: Run a Flask app on Wokku with Gunicorn.
last_updated: 2026-11-07
---

Add Gunicorn, push, and the app is live. Want a working repo first? Deploy the `flask` starter from [Templates](/docs/templates/browse).

## Dependencies

```text
# requirements.txt
flask
gunicorn
```

## Start command

Assuming your app object is `app` in `app.py`:

```procfile
web: gunicorn app:app --bind 0.0.0.0:$PORT
```

## Config and database

```bash
wokku apps:create my-app
wokku config:set my-app SECRET_KEY="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
wokku addons:shared:enable my-app postgres   # optional
```

The add-on sets `DATABASE_URL`; read it in your SQLAlchemy config. See [Create & Link a Database](/docs/databases/create-link).

## Deploy and migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- flask db upgrade   # if you use Flask-Migrate
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **`ModuleNotFoundError`** — add the package to `requirements.txt`.
- **App object not found** — `gunicorn app:app` is `module:variable`; match your file and variable names.
- **Can't reach the database** — check `wokku config my-app` shows `DATABASE_URL`.

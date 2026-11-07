---
title: Common Issues
summary: Run wokku doctor first, then find your symptom below — failed deploys, rejected pushes, sleeping apps, database errors.
last_updated: 2026-11-07
---

Find what's wrong with an app and fix it. Start with `wokku doctor`, then jump to your symptom.

## Start here: `wokku doctor`

```bash
wokku doctor
```

It checks your login, whether your CLI is up to date, the health of the hosts your apps run on, and whether any app has crashed — and prints hints for anything it finds. In Claude Code, ask *"Run wokku doctor"* (uses `wokku_doctor`).

## Deploy fails

1. Read the build log: the app's **Deploy** tab, or
   ```bash
   wokku deploys my-app                    # find the deploy ID
   wokku deploys:info my-app DEPLOY_ID     # show its build log
   ```
2. Ask for a diagnosis: `wokku ai:diagnose my-app`.

Usual causes:

- **Wrong language detected** — Wokku builds your `Dockerfile` if there is one, otherwise it auto-detects with Nixpacks. If detection picks the wrong stack, add a [Dockerfile](/docs/guides/dockerfile).
- **Out of memory during build or start** — give the process more RAM in **Resources** ([Resources](/docs/scaling/resources)).
- **App doesn't listen on `$PORT`** — bind to `0.0.0.0` on the port in the `PORT` env var.

## Push rejected

- **Wrong remote** — it must be `git@git.wokku.cloud:my-app`. Check with `git remote -v`; fix with
  ```bash
  git remote set-url wokku git@git.wokku.cloud:my-app
  ```
- **SSH key not added** — run `wokku ssh-keys:add` or add it under **Profile → SSH Keys**. See [SSH Keys](/docs/apps/ssh-keys).
- **App doesn't exist** — create it first: `wokku apps:create my-app`.
- **Wrong branch** — push the branch the app deploys from, e.g. `git push wokku main`.
- **App is locked** — someone ran `wokku apps:lock my-app`. Unlock with `wokku apps:unlock my-app`.

## Database tables missing after deploy

Wokku doesn't run migrations for you — there's no release phase, and a `release:` line in your Procfile won't run them. Run them after each deploy that changes the schema:

```bash
wokku run my-app -- bin/rails db:migrate        # Rails
wokku run my-app -- python manage.py migrate    # Django
```

## First request is slow (app was asleep)

Free apps (the **Sleeping** size) sleep after 30 minutes without traffic. The next request wakes them; it takes about 30 seconds. To keep an app awake, move it off the Sleeping size in **Resources** — see [Resources](/docs/scaling/resources).

## App not reachable

- **App stopped or crashed** — check the app's **Overview**, then restart: `wokku ps:restart my-app`. Look at `wokku logs my-app` for the crash.
- **Health check failing** — your health check path must return 200. See [Health Checks](/docs/monitoring/health-checks).
- **Custom domain doesn't load** — the DNS record must point at the target shown on the app's domains panel (a CNAME, or an A record for apex domains). HTTPS is issued once DNS resolves. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Can't connect to the database

- **Not linked** — link the database to the app; that sets `DATABASE_URL` (or `REDIS_URL`) for you. See [Create & Link](/docs/databases/create-link).
- **Old credentials** — check `wokku config my-app` shows the URL; unlink and re-link to refresh it.
- **Database stuck provisioning** — `wokku databases:retry DB`.

## Still stuck?

Email [support@wokku.cloud](mailto:support@wokku.cloud) with your app name and the output of `wokku doctor`.

---
title: Create & Deploy
summary: Create an app, push your code with git, and get a live URL at my-app.wokku.app.
last_updated: 2026-11-07
---

You'll create an app, add your SSH key once, and `git push` to deploy.

## 1. Create the app

:::tabs
::web-ui
1. Go to **Apps → + New app**.
2. Enter a name, for example `my-app`.
3. Set **Resources** (CPU and RAM sliders, or a preset). Leave the free size for a hobby app.
4. Optionally tick shared add-ons (Postgres, MariaDB, Redis) or pick a dedicated database.
5. Click **Create App**.

::cli
```bash
wokku apps:create my-app
# with a free shared Postgres and Redis:
wokku apps:create my-app --shared postgres,redis
# with a dedicated database:
wokku apps:create my-app --dedicated-db postgres
```

Other flags: `--branch BRANCH` (default `main`), `--dedicated-redis`.

::api
The API needs a `server_id`. Get it from `GET /api/v1/servers`, then:

```bash
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-app", "server_id": "SERVER_ID", "deploy_branch": "main"}'
```

The response includes `git_remote` and `push_instructions`.

::mcp
Ask Claude: *"Create an app called my-app with a shared Postgres."*
:::

App names use lowercase letters, numbers and hyphens, and must start with a letter.

## 2. Add your SSH key (once)

Git pushes are authenticated by your SSH key.

```bash
wokku ssh-keys:add --name laptop          # uploads ~/.ssh/id_ed25519.pub
```

Or paste it under **Profile → SSH Keys**. See [SSH Keys](/docs/apps/ssh-keys).

## 3. Push your code

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

The remote and push command are also on the app's **Deploy** tab, with copy buttons. When the build finishes, your app is live at `https://my-app.wokku.app`.

No git? Deploy a local folder instead: `wokku deploy:tarball my-app .`

## How the build works

- If your repo has a `Dockerfile` at the root, Wokku builds it. See [Deploy with a Dockerfile](/docs/guides/dockerfile).
- Otherwise Wokku detects your language and builds with [Nixpacks](https://nixpacks.com/docs/providers).
- Your app must listen on `$PORT`.
- A `Procfile` defines process types. `web` gets HTTP traffic; others (like `worker`) run only when you scale them. See [Background Workers](/docs/guides/background-workers).

During a deploy the new container starts before the old one stops, and crashed containers restart automatically.

## Run migrations

There's no release phase, so a `release:` line in your Procfile doesn't run migrations. Run them after the deploy:

```bash
wokku run my-app -- bin/rails db:migrate
```

## Check a deploy

```bash
wokku deploys my-app                   # recent deploys
wokku deploys:info my-app DEPLOY_ID    # one deploy and its build log
wokku logs my-app --follow             # runtime logs
```

In the dashboard, open the app's **Deploy** tab.

## Next steps

- [Auto-deploy from GitHub](/docs/apps/github-autodeploy)
- [Set environment variables](/docs/apps/config)
- [Add a database](/docs/databases/create-link)
- [Add a custom domain](/docs/domains-ssl/custom-domains)

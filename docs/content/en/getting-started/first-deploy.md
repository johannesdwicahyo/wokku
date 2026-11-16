---
cloud_flow: true
cloud_prices: true
title: Quickstart
summary: Go from a new account to a live app at https://my-app.wokku.app, with a one-click template or your own code and git push.
last_updated: 2026-11-07
---

You'll sign up, deploy an app one of two ways, and open it at its live URL. It takes a few minutes.

## 1. Sign up

Go to [wokku.cloud](https://wokku.cloud) and click **Get Started**. You can sign up with email and password, Google, GitHub, or Apple. See [Sign Up](/docs/getting-started/sign-up).

When you have no apps yet, the **Apps** page shows a **Deploy your first app** card. It offers a few one-click picks plus **or push your own code**. The two options below match those choices.

## 2a. Deploy a one-click template

This is the fastest way to see something live. Templates are ready-made apps such as Ghost, n8n, or an Astro or Next.js starter.

:::tabs
::web-ui
1. On the **Deploy your first app** card, pick a template. You can also go to **Templates** in the sidebar and choose any app.
2. Keep the suggested app name or type your own, for example `my-app`.
3. Click **Deploy &lt;template name&gt;**.

The build usually takes 30–90 seconds, depending on the stack.

::cli
```bash
wokku templates                    # list templates and their slugs
wokku deploy ghost --name my-app
```

::api
```bash
# Get your server id first: GET /api/v1/servers
curl -X POST https://wokku.cloud/api/v1/templates/deploy \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug": "ghost", "name": "my-app", "server_id": "<server-id>"}'
```

::mcp
Ask Claude: *"Deploy the Ghost template as my-app."*
:::

To find more apps, see [One-Click Apps](/docs/templates/browse).

## 2b. Push your own code

Wokku builds from your `Dockerfile` if the repo has one. Otherwise it detects your stack and builds the app for you. Your app should listen on the port in the `PORT` environment variable.

### Add your SSH key (once)

The git server recognises you by your SSH key, so add it before your first push.

:::tabs
::web-ui
Go to **Settings → SSH Keys** and paste your public key, usually the contents of `~/.ssh/id_ed25519.pub`.

::cli
```bash
gem install wokku-cli
wokku auth:login
wokku ssh-keys:add --name laptop     # uploads ~/.ssh/id_ed25519.pub
```

::mcp
Ask Claude: *"Add my SSH public key from ~/.ssh/id_ed25519.pub to Wokku as laptop."*
:::

No key yet? Run `ssh-keygen -t ed25519` first. More options are in [SSH Keys](/docs/apps/ssh-keys).

### Create the app and push

:::tabs
::web-ui
1. On **Apps**, click **+ New app**, or click **or push your own code** on the first-deploy card.
2. Enter a name, for example `my-app`. To stay free, leave **Resources** on **Sleeping**.
3. Click **Create App**. Then open the app's **Deploy** tab and copy the `git remote add` line.
4. In your project folder, run:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::cli
```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::api
```bash
# Get your server id first: GET /api/v1/servers
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-app", "server_id": "<server-id>"}'
```

Then push:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::mcp
Ask Claude: *"Create a Wokku app called my-app."* Then push from your terminal:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```
:::

The build log streams to your terminal. If you'd rather deploy on every GitHub push, use **Connect repository** on the app's **Deploy** tab. See [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

## 3. Open your app

Your app is live at:

```
https://my-app.wokku.app
```

:::callout note
**Free apps sleep.** An app on the free **Sleeping** size goes to sleep after 30 minutes without traffic. The next request wakes it, which takes about 30 seconds. You get 3 sleeping apps for free. To keep an app always on, give it CPU and RAM under **Resources**. You pay only for what you run; see [Pricing](/docs/billing/pricing).
:::

## Next steps

| To do this | Read |
|---|---|
| Add a free Postgres, MariaDB, or Redis | [Create & Link a Database](/docs/databases/create-link) |
| Set environment variables | [Environment Variables](/docs/apps/config) |
| Run migrations or other one-off commands with `wokku run my-app -- <cmd>` | [Create & Deploy](/docs/apps/deploy) |
| Use your own domain | [Custom Domains](/docs/domains-ssl/custom-domains) |
| Change CPU and RAM | [Resources](/docs/scaling/resources) |
| Get tips for your framework | [Frameworks](/docs/frameworks/index) |

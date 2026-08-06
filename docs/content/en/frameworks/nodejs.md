# Deploy Node.js / Express

Deploy any Node HTTP server (Express, Fastify, Koa, Hono, plain `http`) to Wokku.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Node app with a `package.json`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-node-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-node-app --server my-server
```
:::

## 2. Prepare your app

The Node buildpack reads `package.json`. Provide a `start` script and listen on
`process.env.PORT`:

```json
{
  "scripts": { "start": "node server.js" },
  "engines": { "node": ">=20" }
}
```

```js
const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`listening on ${port}`));
```

:::callout warn
Always bind to `process.env.PORT`. A hardcoded port is the #1 reason a Node app
boots locally but crashes on Wokku.
:::

Optionally pin the start command with a `Procfile`:

```procfile
web: npm start
```

## 3. Environment variables

:::tabs
::web-ui
App → **Config** → add `NODE_ENV=production` and your secrets.

::cli
```bash
wokku config:set my-node-app NODE_ENV=production
```
:::

## 4. Add a database (optional)

```bash
wokku addons:create postgres my-node-app
```

Read `process.env.DATABASE_URL` in your `pg`/Prisma/Drizzle client. See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-node-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-node-app
git push wokku main
```
:::

Live at `https://my-node-app.wokku.app`.

## Add a custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **Crashes on boot** — hardcoded port. Use `process.env.PORT`.
- **`npm ci` fails** — commit your `package-lock.json`.
- **Wrong Node version** — pin it via `"engines": { "node": ... }`.

## Next steps

- [Background workers](/docs/scaling/bundled-processes) · [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)

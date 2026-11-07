---
title: Environment Variables
summary: Set, view and remove your app's environment variables, then restart to apply them.
last_updated: 2026-11-07
---

You'll set config vars for your app and restart it so they take effect.

:::callout note
Changes apply on the next restart or deploy. Restart with `wokku ps:restart my-app` or the **restart** button. See [Restart / Stop / Start](/docs/apps/lifecycle).
:::

## View

:::tabs
::web-ui
Open your app → **Deploy** tab → **Config**.

::cli
```bash
wokku config my-app                  # all vars
wokku config:get my-app SECRET_KEY   # one var
wokku config:export my-app > .env    # as a .env file
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Show the environment variables for my-app."*
:::

Team members with the viewer role see variable names but not values.

## Set

:::tabs
::web-ui
**Deploy** tab → **Config** → add the key and value → save.

::cli
```bash
wokku config:set my-app SECRET_KEY=abc123 LOG_LEVEL=info
```

::api
```bash
curl -X PUT https://wokku.cloud/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vars": {"SECRET_KEY": "abc123", "LOG_LEVEL": "info"}}'
```

::mcp
Ask Claude: *"Set LOG_LEVEL=info on my-app."*
:::

## Remove

:::tabs
::web-ui
**Deploy** tab → **Config** → delete icon next to the variable.

::cli
```bash
wokku config:unset my-app LEGACY_KEY OLD_SECRET
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["LEGACY_KEY"]}'
```

::mcp
Ask Claude: *"Remove LEGACY_KEY from my-app."*
:::

## Set for you

| Variable | When |
|----------|------|
| `PORT` | Always. Your app must listen on it. |
| `DATABASE_URL` | When you add or link a Postgres, MySQL or MariaDB database |
| `REDIS_URL` | When you add or link Redis |

All process types (`web`, `worker`, …) share the same variables.

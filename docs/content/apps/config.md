# Environment Variables

Set, view, and remove environment variables for your apps.

## View Config

:::tabs
::web-ui
Go to your app → **Config** tab.

::cli
```bash
wokku config my-app
```

::api
```bash
curl https://wokku.dev/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Show environment variables for my-app"*

::mobile
Tap your app → **Config** tab.
:::

## Set Variables

Setting a variable triggers an app restart.

:::tabs
::web-ui
Go to **Config → Add Variable**. Enter the key and value, click **Save**.

::cli
```bash
wokku config:set my-app DATABASE_URL=postgres://user:pass@host/db
wokku config:set my-app REDIS_URL=redis://host:6379 SECRET_KEY=abc123
```

::api
```bash
curl -X PUT https://wokku.dev/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"DATABASE_URL": "postgres://user:pass@host/db"}'
```

::mcp
Ask Claude: *"Set DATABASE_URL on my-app to postgres://user:pass@host/db"*

::mobile
Tap your app → Config → **+** to add a variable.
:::

## Remove Variables

:::tabs
::web-ui
Go to **Config**, click the delete icon next to the variable.

::cli
```bash
wokku config:unset my-app LEGACY_KEY OLD_SECRET
```

::api
```bash
curl -X DELETE https://wokku.dev/api/v1/apps/my-app/config \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"keys": ["LEGACY_KEY"]}'
```

::mcp
Ask Claude: *"Remove the LEGACY_KEY env var from my-app"*

::mobile
Tap your app → Config → swipe to delete.
:::

## Common Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Auto-set when you link a database |
| `REDIS_URL` | Auto-set when you link Redis |
| `SECRET_KEY_BASE` | Rails secret key |
| `NODE_ENV` | Node.js environment |
| `PORT` | Set automatically by Dokku |

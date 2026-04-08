# Create & Link

Create databases and link them to your apps.

## Create a Database

:::tabs
::web-ui
Go to **Resources → New Database**. Select the engine, name it, and choose a server.

::cli
```bash
wokku addons:create postgres my-db --server my-server
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/databases \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"service_type": "postgres", "name": "my-db", "server_id": 1}'
```

::mcp
Ask Claude: *"Create a PostgreSQL database called my-db on server 1"*

::mobile
Tap **Resources → +** → select engine → name it → create.
:::

## Link to an App

Linking injects the connection URL as an environment variable and restarts the app.

:::tabs
::web-ui
Go to the database detail page → **Link** → select the app.

::cli
```bash
wokku addons:add my-app postgres --name my-db
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/databases/DB_ID/link \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"app_id": "my-app"}'
```

::mcp
Ask Claude: *"Link my-db database to my-app"*

::mobile
Tap the database → **Link** → select app.
:::

## Unlink

Removes the connection URL from the app and restarts it.

:::tabs
::web-ui
Go to the database → **Unlink** next to the linked app.

::cli
```bash
wokku addons:remove my-app my-db
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/databases/DB_ID/unlink \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"app_id": "my-app"}'
```

::mcp
Ask Claude: *"Unlink my-db from my-app"*

::mobile
Tap the database → swipe on the linked app to unlink.
:::

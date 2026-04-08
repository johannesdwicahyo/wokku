# Process Types & Dynos

Scale your app's web and worker processes.

## Process Types

| Type | Purpose |
|------|---------|
| **web** | Handles HTTP requests |
| **worker** | Runs background jobs |

Process types are defined in your `Procfile`:

```
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
```

## View Current State

:::tabs
::web-ui
Go to your app → **Scaling** tab.

::cli
```bash
wokku ps my-app
```

::api
```bash
curl https://wokku.dev/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Show the process state for my-app"*

::mobile
Tap your app → **Scaling** tab.
:::

## Scale

:::tabs
::web-ui
Go to **Scaling** → adjust the dyno count → **Save**.

::cli
```bash
wokku ps:scale my-app web=2 worker=1
```

::api
```bash
curl -X PUT https://wokku.dev/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"scaling": {"web": 2, "worker": 1}}'
```

::mcp
Ask Claude: *"Scale my-app to 2 web dynos and 1 worker"*

::mobile
Tap your app → Scaling → adjust counts → Save.
:::

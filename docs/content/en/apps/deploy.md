# Deploy

Deploy your code to Wokku using git push, GitHub, or Docker images.

## Git Push

Push code to Wokku's SSH git gateway — it authenticates you by your
registered SSH key, authorizes against your team's access to the app,
and proxies the push to the underlying Dokku host. You don't need to
know which server your app is running on.

Register your public key under **Profile → SSH Keys** before pushing for
the first time.

:::tabs
::web-ui
Copy the git remote URL from your app's overview page, then push from your terminal:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Watch the deploy progress in real-time from the **Deploys** tab.

::cli
```bash
wokku apps:info my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'
```

Then deploy with git push.

::mcp
Ask Claude: *"What's the git URL for my-app?"*

Then push with git from your terminal.

::mobile
View deploy status and logs from the app detail screen. Deploys are triggered via git push.
:::

## Buildpack Detection

Dokku automatically detects your app's language:

| Language | Detection |
|----------|-----------|
| Node.js | `package.json` in root |
| Python | `requirements.txt` or `Pipfile` |
| Ruby | `Gemfile` in root |
| Go | `go.mod` in root |
| PHP | `composer.json` in root |
| Java | `pom.xml` or `build.gradle` |
| Static | `index.html` in root |

You can also use a `Dockerfile` for full control over the build.

## Zero-Downtime Deploys

Dokku performs zero-downtime deploys by default. The new container starts, health checks pass, then traffic switches over.

See [Health Checks](/docs/monitoring/health-checks) to configure deploy checks.

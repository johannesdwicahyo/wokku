---
title: API Authentication
summary: Create an API token and send it as a Bearer header on every request.
eyebrow: api
last_updated: 2026-11-07
---

Get an API token, then send it in the `Authorization` header of every request to `https://wokku.cloud/api/v1`.

## Create a token

:::tabs
::web-ui
1. Open **Profile** in the dashboard.
2. Under **API Tokens**, enter a name and create the token.
3. Copy it now — it is shown only once.
::cli
```bash
wokku tokens:create ci
```
The token is printed once. Copy it now.
::api
With an existing token:

```bash
curl -X POST https://wokku.cloud/api/v1/auth/tokens \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "ci"}'
```

```json
{"id": "…", "token": "…", "name": "ci"}
```

Add `"expires_at"` (an ISO 8601 time) to make the token expire.
::mcp
*"Create a Wokku API token called ci"*
:::

## Use the token

```bash
curl https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

Check who a token belongs to:

```bash
curl https://wokku.cloud/api/v1/auth/whoami \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

A token can do whatever its user can do, in every team the user belongs to.

## Sign in a tool through the browser (device flow)

If you are building a tool that runs on someone's machine, let them approve it in the browser instead of pasting a token. This is how `wokku auth:login` works.

1. Request a code:
   ```bash
   curl -X POST https://wokku.cloud/api/v1/auth/device/code
   ```
   The response has a `device_code`, a `user_code`, a `verification_uri_complete` link, `expires_in` and `interval` (seconds).
2. Show the user the link and code. They open it, sign in and approve.
3. Poll every `interval` seconds:
   ```bash
   curl -X POST https://wokku.cloud/api/v1/auth/device/token \
     -H "Content-Type: application/json" \
     -d '{"device_code": "…"}'
   ```
   While waiting you get `{"error": "authorization_pending"}`. Once approved you get `{"token": "…", "user": {…}}` — this is the only time the token is returned. `slow_down` means poll less often; `access_denied` or `expired_token` means start again.

## Revoke a token

:::tabs
::web-ui
**Profile → API Tokens**, then revoke the token.
::cli
```bash
wokku tokens            # find the ID
wokku tokens:revoke TOKEN_ID
```
::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/auth/tokens/TOKEN_ID \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```
::mcp
*"Revoke my Wokku API token called ci"*
:::

Anything using a revoked token stops working immediately.

## Errors and limits

Failed requests return JSON in one shape:

```json
{"error": "Invalid or expired token", "error_code": "invalid_token", "hint": "…", "retryable": false}
```

Requests are limited to 60 per minute per IP address.

## Next

- [Endpoints](/docs/api/endpoints)
- Full reference: [`/api/v1/openapi.yaml`](https://wokku.cloud/api/v1/openapi.yaml)

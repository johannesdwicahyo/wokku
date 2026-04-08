# Authentication

All API requests require a Bearer token.

## Get a Session Token

```bash
curl -X POST https://wokku.dev/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "your-password"}'
```

Response:

```json
{"token": "eyJ...", "user": {"id": 1, "email": "you@example.com"}}
```

## Create an API Token

For long-lived access, create an API token:

```bash
curl -X POST https://wokku.dev/api/v1/auth/tokens \
  -H "Authorization: Bearer SESSION_TOKEN" \
  -d '{"name": "my-token"}'
```

Response:

```json
{"id": 1, "token": "wokku_abc123...", "name": "my-token"}
```

Save the `token` value — it's only shown once.

## Using Tokens

Include the token in the `Authorization` header:

```bash
curl https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer wokku_abc123..."
```

## Verify Your Token

```bash
curl https://wokku.dev/api/v1/auth/whoami \
  -H "Authorization: Bearer $TOKEN"
```

## Revoke a Token

```bash
curl -X DELETE https://wokku.dev/api/v1/auth/tokens/TOKEN_ID \
  -H "Authorization: Bearer $TOKEN"
```

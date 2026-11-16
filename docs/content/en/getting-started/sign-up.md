---
cloud_flow: true
title: Sign Up
summary: Create your Wokku account in the browser, then optionally sign in from the CLI or Claude.
last_updated: 2026-11-07
---

You'll create an account on wokku.cloud and, if you like, connect the CLI or Claude to it.

## Create your account

1. Go to [wokku.cloud](https://wokku.cloud) and click **Get Started**.
2. Choose how to sign up:
   - **Email and password**
   - **Google**
   - **GitHub**
   - **Apple**
3. You land on your dashboard, ready for your [first deploy](/docs/getting-started/first-deploy).

Accounts are created in the browser only. The CLI and API sign in to an account you already have.

## Sign in from other tools (optional)

:::tabs
::cli
```bash
gem install wokku-cli
wokku auth:login       # opens your browser to approve the login
wokku auth:whoami      # check who you're signed in as
```

See [Install the CLI](/docs/cli/install).

::api
Create a token under **Settings → API Tokens**, then send it as a bearer token:

```bash
curl https://wokku.cloud/api/v1/auth/whoami \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

See [Authentication](/docs/api/authentication).

::mcp
The Claude Code plugin uses an API token. Create one under **Settings → API Tokens**, then follow [Claude Code Setup](/docs/mcp/setup).
:::

## Turn on two-factor authentication

Go to **Settings → Security** and click **Enable 2FA**. Scan the code with any authenticator app.
